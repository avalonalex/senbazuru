module HingeSweepSpec (spec) where

import ContactDiscovery
import ContactExample
import Control.Monad (forM_)
import Data.Either (isLeft)
import FoldRelaxation (maxLengthError)
import HingeSweep
import PanelContact (checkTriangleContact, contactPassed)
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck (choose, forAll)

spec :: Spec
spec = describe "rigid hinge sweep contact" $ do
  it "clears each interval of the opposing-flap approach" $ do
    forM_ [(105, 110), (110, 115), (115, 120), (120, 121)] $ \(from, to) -> do
      start <- fixtureMesh 145 from
      finish <- fixtureMesh 145 to
      sweep <- right (rightSweep start (to - from))
      result <- right (checkSweep defaultSweepSettings sweep)
      sweepOutcome result `shouldBe` SweepClear
      endpoint <- right (sweepMeshAt sweep 1)
      maximumDifference endpoint finish `shouldSatisfy` (< 1e-12)
      forM_ [0, 0.25, 0.5, 0.75, 1] $ \t -> do
        current <- right (sweepMeshAt sweep t)
        triangles current `shouldBe` triangles start
        map sampleMaterial (samples current) `shouldBe` map sampleMaterial (samples start)
        maxLengthError current `shouldSatisfy` (< 1e-12)

  it "blocks a full turn whose endpoints coincide but whose interior crosses" $ do
    fixture <- right (opposingFlaps 1)
    let refined = exampleRefined fixture
        mesh = refinedMesh refined
        owners = refinedPanels refined
    sweep <- right (rightSweep mesh 360)
    endpoint <- right (sweepMeshAt sweep 1)
    maximumDifference endpoint mesh `shouldSatisfy` (< 1e-12)
    forM_ [mesh, endpoint] $ \current -> do
      report <- right (checkTriangleContact (V3 0 0 1) [] owners current)
      contactPassed report `shouldBe` True
    result <- right (checkSweep defaultSweepSettings sweep)
    case sweepOutcome result of
      SweepCollision t pairs -> do
        t `shouldSatisfy` (\value -> value > 0 && value < 1)
        pairs `shouldSatisfy` (not . null)
        witness <- right (sweepMeshAt sweep t)
        report <- right (checkTriangleContact (V3 0 0 1) [] owners witness)
        contactPassed report `shouldBe` False
      other -> expectationFailure (show other)

  it "includes angular extrema inside an interval and handles negative travel" $ do
    sinusoidRange 1 0 (-(pi / 4)) (pi / 4) `shouldBe` Right (cos (pi / 4), 1)
    sinusoidRange 0 1 0 pi `shouldBe` Right (0, 1)
    sinusoidRange 0 1 pi 0 `shouldBe` Right (0, 1)
    sinusoidRange 3 4 0 (2 * pi) `shouldBe` Right (-5, 5)
    start <- fixtureMesh 145 121
    sweep <- right (rightSweep start (-16))
    result <- right (checkSweep defaultSweepSettings sweep)
    sweepOutcome result `shouldBe` SweepClear

  it "does not turn an exhausted interval into a pass" $ do
    start <- fixtureMesh 145 105
    sweep <- right (rightSweep start 360)
    result <- right (checkSweep (SweepSettings 0 1) sweep)
    case sweepOutcome result of
      SweepUnresolved _ _ pairs -> pairs `shouldSatisfy` (not . null)
      other -> expectationFailure (show other)

  it "is unchanged when the entire motion is rotated and translated" $ do
    start <- fixtureMesh 145 105
    let rotate (V3 x y z) = V3 z x y
        move p = rotate p ^+^ V3 3 (-2) 5
        moved = start {samples = [s {position = move (position s)} | s <- samples start]}
    forM_ [16, 360] $ \angle -> do
      sweep <- right (prepareSweep (move (V3 0.7 0 0)) (rotate (V3 0 (-1) 0)) (angle * pi / 180) (rightIds start) moved)
      result <- right (checkSweep defaultSweepSettings sweep)
      if angle == 16
        then sweepOutcome result `shouldBe` SweepClear
        else case sweepOutcome result of
          SweepCollision _ _ -> pure ()
          other -> expectationFailure (show other)

  it "rejects triangles that would tear or stretch away from the hinge" $ do
    start <- fixtureMesh 145 105
    prepareSweep (V3 0 0 0) (V3 0 1 0) 1 (rightIds start) start `shouldSatisfy` isLeft
    prepareSweep (V3 0.7 0 0) (V3 0 (-1) 0) 1 [3] start `shouldSatisfy` isLeft

  prop "bounds every interior sample of finite sinusoid intervals" $
    forAll (choose (-10, 10)) $ \a -> forAll (choose (-10, 10)) $ \b ->
      forAll (choose (-(2 * pi), 2 * pi)) $ \from -> forAll (choose (-(2 * pi), 2 * pi)) $ \to ->
        case sinusoidRange a b from to of
          Left _ -> False
          Right (lo, hi) -> all (\t -> let angle = from + t * (to - from); value = a * cos angle + b * sin angle in value >= lo - 1e-12 && value <= hi + 1e-12) [0, 0.125 .. 1]

  it "reports interval work-budget exhaustion" $ do
    start <- fixtureMesh 145 105
    sweep <- right (rightSweep start 360)
    result <- right (checkSweep (SweepSettings 20 1) sweep)
    case sweepOutcome result of
      SweepUnresolved {} -> sweepIntervals result `shouldBe` 1
      other -> expectationFailure (show other)

  it "does not skip a crossing pair just because it shares a material vertex" $ do
    let mesh = Mesh [Sample (V2 x y) (V3 x y z) | (x, y, z) <- [(-2, -2, 0), (2, -2, 0), (0, 3, 0), (0, 0, -1), (0, 1, 1)]] [(0, 1, 2), (0, 3, 4)]
    sweep <- right (prepareSweep (V3 0 0 5) (V3 0 1 0) 0 [] mesh)
    result <- right (checkSweep defaultSweepSettings sweep)
    sweepOutcome result `shouldBe` SweepCollision 0 [(0, 1)]

  it "does not exempt moving triangles that share only a corner" $ do
    let mesh = Mesh [Sample (V2 x y) (V3 x y z) | (x, y, z) <- [(0, 0, 0), (2, 0, 0), (0, 2, 0), (1, -1, 1), (1, 1, 2)]] [(0, 1, 2), (0, 3, 4)]
    sweep <- right (prepareSweep (V3 0 0 0) (V3 0 1 0) (2 * pi) [3, 4] mesh)
    result <- right (checkSweep defaultSweepSettings sweep)
    sweepOutcome result `shouldNotBe` SweepClear

  it "does not assume a corner-attached rotation axis lies in the stationary plane" $ do
    -- The moving triangle has a second fixed vertex below the plane. Its
    -- turning vertex stays above, but their connecting edge sweeps through
    -- the stationary triangle. A crease-plane exemption would be false here.
    let mesh = Mesh [Sample (V2 x y) (V3 x y z) | (x, y, z) <- [(0, 0, 0), (2, 0.2, 0), (0, 2, 0), (-1, 0, -1), (2, -1, 2)]] [(0, 1, 2), (0, 3, 4)]
    sweep <- right (prepareSweep (V3 0 0 0) (V3 1 0 1) (2 * pi) [3, 4] mesh)
    result <- right (checkSweep defaultSweepSettings sweep)
    sweepOutcome result `shouldNotBe` SweepClear

  it "records cleared intervals and refuses unsafe or unrelated motion without changing history" $ do
    poses <- right (opposingApproach 1)
    lastPose <- case reverse poses of p : _ -> pure p; [] -> fail "no approach"
    map (fmap sweepOutcome . observationMotion) (referenceObservations (approachHistory lastPose)) `shouldBe` [Nothing, Just SweepClear, Just SweepClear, Just SweepClear, Just SweepClear]
    fixture <- right (opposingFlaps 1)
    let refined = exampleRefined fixture
        mesh = refinedMesh refined
    reference <- right (discoverReference (exampleClearance fixture) (V3 0 0 1) (refinedPanels refined) mesh)
    fullTurn <- right (rightSweep mesh 360)
    observeContactPose reference mesh `shouldSatisfy` (not . isLeft)
    observeContactSweep defaultSweepSettings reference fullTurn mesh `shouldSatisfy` isLeft
    observeContactSweep (SweepSettings 0 1) reference fullTurn mesh `shouldSatisfy` isLeft
    length (referenceObservations reference) `shouldBe` 1
    next <- fixtureMesh 145 110
    motion <- right (rightSweep mesh 5)
    accepted <- right (observeContactSweep defaultSweepSettings reference motion next)
    length (referenceObservations accepted) `shouldBe` 2
    observeContactSweep defaultSweepSettings accepted motion next `shouldBe` Left MotionStartMismatch
    observeContactSweep defaultSweepSettings reference motion mesh `shouldBe` Left MotionEndMismatch
    let remapped = next {samples = [p {sampleMaterial = V2 9 9} | p <- samples next]}
    observeContactSweep defaultSweepSettings reference motion remapped `shouldBe` Left MotionEndMismatch

  it "rejects invalid motion inputs before checking intervals" $ do
    start <- fixtureMesh 145 105
    sinusoidRange (0 / 0) 0 0 1 `shouldBe` Left InvalidSweepRange
    sinusoidRange 1 0 0 (1 / 0) `shouldBe` Left InvalidSweepRange
    rightSweep start (0 / 0) `shouldBe` Left InvalidSweepAngle
    rightSweep start 361 `shouldBe` Left InvalidSweepAngle
    prepareSweep (V3 0 0 0) (V3 0 0 0) 1 [] start `shouldBe` Left InvalidSweepAxis
    prepareSweep (V3 0 0 0) (V3 0 1 0) 1 [999] start `shouldBe` Left (MissingSweepVertex 999)
    sweep <- right (rightSweep start 16)
    sweepMeshAt sweep (-0.1) `shouldBe` Left InvalidSweepProgress
    sweepMeshAt sweep (0 / 0) `shouldBe` Left InvalidSweepProgress
    checkSweep (SweepSettings 0 0) sweep `shouldBe` Left InvalidSweepSettings
    checkSweep (SweepSettings 31 10) sweep `shouldBe` Left InvalidSweepSettings

fixtureMesh :: Double -> Double -> IO MaterialMesh
fixtureMesh leftAngle rightAngle = refinedMesh . exampleRefined <$> right (opposingFlapsAt 1 leftAngle rightAngle)

rightIds :: MaterialMesh -> [Int]
rightIds mesh = [i | (i, s) <- zip [0 ..] (samples mesh), let V2 u _ = sampleMaterial s, u >= 0.7]

rightSweep :: MaterialMesh -> Double -> Either SweepError HingeSweep
rightSweep mesh angle = prepareSweep (V3 0.7 0 0) (V3 0 (-1) 0) (angle * pi / 180) (rightIds mesh) mesh

maximumDifference :: MaterialMesh -> MaterialMesh -> Double
maximumDifference a b = maximum (0 : zipWith (\x y -> norm (position x ^-^ position y)) (samples a) (samples b))

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
