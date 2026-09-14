-- | Test stored geometry, not just a quadratic's numerical residual. The
-- independent whole-sheet checker and authored angles also gate endpoints.
module CreaseInequalitySpec (spec) where

import ClosedCrease
import ContactQuadratic
import Control.Monad (forM_, when)
import CreaseCorrection
import CreaseInequality
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import FoldBending
import FoldRelaxation
import Senbazuru.Fold.Types (FaceId (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Surface
import Test.Hspec

spec :: Spec
spec = describe "nonnegative crease contact" $ do
  it "rounds heights outward by at most one representable value" $ do
    forM_ [0, 1, -1, 1 / 10, -(1 / 10), 1 + 1 / 2 ^ (54 :: Int), -1 + 1 / 2 ^ (54 :: Int), 1 / 2 ^ (1075 :: Int), -(1 / 2 ^ (1075 :: Int))] $ \target -> do
      value <- right (ceilingDouble target)
      toRational value `shouldSatisfy` (>= target)
      let nearest = fromRational target :: Double
          (_, power) = decodeFloat nearest
          spacing = max (encodeFloat 1 (-1074)) (encodeFloat 1 power)
      value - nearest `shouldSatisfy` (<= spacing)
    forM_ [0, 1, -1, 0.125, -0.125] $ \value -> ceilingDouble (toRational value) `shouldBe` Right value
    ceilingDouble (10 ^ (400 :: Int)) `shouldSatisfy` isLeft

  it "retains convex material witnesses through exact clipping" $ do
    fixture <- right (creaseCorrection 2 PenetratingGuess)
    audit <- right (auditLowerGap fixture (correctionSeed fixture))
    forM_ (gapWitnesses audit) $ \w -> do
      sum (witnessWeights w) `shouldBe` 1
      IM.elems (witnessWeights w) `shouldSatisfy` all (>= 0)
      IM.keys (witnessWeights w) `shouldSatisfy` all (\i -> i >= 0 && i < length (samples (correctionSeed fixture)))

  it "repairs all valid starts without moving holds, material coordinates or horizontal positions" $
    forM_ [(n, c) | n <- [1, 2], c <- [ReferenceStart, PenetratingGuess, TinyPenetration]] $ \(n, control) -> do
      fixture <- right (creaseCorrection n control)
      repair <- right (restoreFeasible fixture (correctionSeed fixture))
      let mesh = repairedMesh repair
          seed = correctionSeed fixture
          xy p = let V3 x y _ = position p in (x, y)
      triangles mesh `shouldBe` triangles seed
      map sampleMaterial (samples mesh) `shouldBe` map sampleMaterial (samples seed)
      map xy (samples mesh) `shouldBe` map xy (samples seed)
      held fixture mesh
      gap <- right (auditLowerGap fixture mesh)
      minimumGap gap `shouldBe` 0
      let expected :: Double
          expected = case control of ReferenceStart -> 0; TinyPenetration -> 2e-8; _ -> 0.002
      abs (fromRational (commonLift repair) - expected) `shouldSatisfy` (< 1e-15)
      again <- right (restoreFeasible fixture mesh)
      repairedMesh again `shouldBe` mesh
      commonLift again `shouldBe` 0

  it "refuses an impossible hold and missing or displaced lower holds" $ do
    forM_ [1, 2] $ \n -> do
      impossible <- right (creaseCorrection n ConflictingHold)
      solveInequality (Settings 40 1e-5) impossible `shouldSatisfy` isLeft
    fixture <- right (creaseCorrection 1 ReferenceStart)
    let seed = correctionSeed fixture
        missing = fixture {correctionPins = IM.empty}
        displaced = fixture {correctionPins = IM.map (const (V3 0 0 99)) (correctionPins fixture)}
    restoreFeasible missing seed `shouldSatisfy` isLeft
    restoreFeasible displaced seed `shouldSatisfy` isLeft

  it "converges at both resolutions with exact order, lengths, angles and whole-sheet contact" $
    forM_ [1, 2] $ \n -> do
      fixture <- right (creaseCorrection n PenetratingGuess)
      result <- right (solveInequality (Settings 40 1e-5) fixture)
      let mesh = inequalityMesh result
          vertices = IM.fromList (zip [0 ..] (samples mesh))
      inequalityConverged result `shouldBe` True
      maxLengthError mesh `shouldSatisfy` (<= 1e-5)
      held fixture mesh
      audit <- right (auditLowerGap fixture mesh)
      minimumGap audit `shouldBe` 0
      contact <- right (checkTriangleContact (V3 0 0 1) [(FaceId 0, FaceId 1)] (closedOwners (correctionReference fixture)) mesh)
      contactPassed contact `shouldBe` True
      forM_ [h | h <- closedHinges (correctionReference fixture), SurfaceCrease _ <- [hingeRole h]] $ \h -> do
        (angle, _) <- right (hingeAngle h vertices)
        abs (angleError angle pi) `shouldSatisfy` (<= 1e-5)
      exported <- right (correctionSurface fixture mesh)
      surfaceSamples exported `shouldBe` samples mesh
      forM_ (inequalitySteps result) $ \step -> do
        stepMinGap step `shouldSatisfy` (>= 0)
        when (stepAccepted step) $ stepEnergyAfter step `shouldSatisfy` (< stepEnergyBefore step)
      case reverse (inequalitySteps result) of
        [] -> expectationFailure "missing final convergence evidence"
        final : _ -> do
          stepWeight final `shouldBe` 1e8
          quadraticConverged (stepQuadratic final) `shouldBe` True
          stepMovement final `shouldSatisfy` (<= 1e-7)
          stepSettled final `shouldBe` True

  it "refuses invalid settings and distinguishes budget exhaustion from convergence" $ do
    fixture <- right (creaseCorrection 1 PenetratingGuess)
    forM_ [Settings 0 1e-5, Settings 40 (-1), Settings 40 (0 / 0)] $ \settings -> solveInequality settings fixture `shouldSatisfy` isLeft
    result <- right (solveInequality (Settings 1 1e-5) fixture)
    inequalityConverged result `shouldBe` False
    audit <- right (auditLowerGap fixture (inequalityMesh result))
    minimumGap audit `shouldSatisfy` (>= 0)

held :: CreaseCorrection -> MaterialMesh -> Expectation
held fixture mesh = do
  let points = IM.fromList (zip [0 ..] (map position (samples mesh)))
  forM_ (IM.toList (correctionPins fixture)) $ \(i, p) -> IM.lookup i points `shouldBe` Just p

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
