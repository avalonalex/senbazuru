-- | Distinguish releasing contact from changing the material controls. The
-- contact-off lower panel should match the baseline; enforcing order changes
-- that response without changing a hold or the added upper springs.
module UnequalCreaseSpec (spec) where

import ClosedCrease
import ContactQuadratic
import Control.Monad (forM_, when)
import CoupledCrease
import CreaseInequality
import CreasePairContact
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.List (sort)
import FoldBending
import FoldMaterial (componentCount)
import FoldRelaxation
import Senbazuru.Fold.Types (FaceId (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Surface
import Test.Hspec
import UnequalCrease

spec :: Spec
spec = describe "unequal controls beside one closed crease" $ do
  it "holds the crease-adjacent strip and outer edge on both resolutions" $
    forM_ [(n, c) | n <- [1, 2], c <- [MatchedHolds, OpenUpperGrip, UpperCurl, CurlWithoutContact]] $ \(n, c) -> do
      f <- right (unequalCrease n c)
      let mesh = coupledSeed f
      forM_ (zip [0 ..] (samples mesh)) $ \(i, p) ->
        IM.member i (coupledPins f) `shouldBe` (abs (materialU p) <= 0.125 || abs (materialU p) == 0.5)
      checkCoupledMaterial f mesh `shouldBe` Right ()
      maxLengthError mesh `shouldSatisfy` (< 1e-12)
      f0 <- right (unequalCrease n MatchedHolds)
      forM_ (zip (samples (coupledSeed f0)) (samples mesh)) $ \(a, b) ->
        when (abs (materialU a) <= 0.125 || materialU a > 0) $ position a `shouldBe` position b

  it "keeps six explicit upper bend controls equally strong under refinement" $ do
    strengths <-
      mapM
        ( \n -> do
            f <- right (unequalCrease n UpperCurl)
            off <- right (unequalCrease n CurlWithoutContact)
            let ref = coupledReference f
                springs = [h | h <- closedHinges ref, hingeRole h == BendControl]
                vertices = IM.fromList (zip [0 ..] (samples (coupledSeed f)))
            coupledSeed f `shouldBe` coupledSeed off
            coupledPins f `shouldBe` coupledPins off
            closedHinges ref `shouldBe` closedHinges (coupledReference off)
            length springs `shouldBe` 6
            forM_ springs $ \h -> do
              let (a, b, _, _) = hingeVertices h
              forM_ [a, b] $ \i -> maybe (expectationFailure "missing control vertex") (\p -> materialU p `shouldSatisfy` (< 0)) (IM.lookup i vertices)
              (angle, _) <- right (hingeAngle h vertices)
              hingeRest h `shouldBe` 2 * angle
            pure (sort (map hingeStiffness springs))
        )
        [1, 2]
    strengths `shouldBe` replicate 2 (replicate 6 4)

  it "preserves the physical controls and shared crease while refining either direction" $
    forM_ [(1, 1), (2, 1), (4, 1), (1, 2), (2, 2)] $ \(n, w) -> do
      f <- right (unequalCreaseWithWidth n w UpperCurl)
      off <- right (unequalCreaseWithWidth n w CurlWithoutContact)
      let mesh = coupledSeed f
          ref = coupledReference f
          springs = [h | h <- closedHinges ref, hingeRole h == BendControl]
          vertices = IM.fromList (zip [0 ..] (samples mesh))
          roots = closedRoot ref
      length (triangles mesh) `shouldBe` 32 * n * w
      componentCount mesh `shouldBe` 1
      length roots `shouldBe` 2 * w + 1
      roots `shouldBe` [i | (i, p) <- zip [0 ..] (samples mesh), materialU p == 0]
      maxLengthError mesh `shouldSatisfy` (< 1e-12)
      coupledSeed off `shouldBe` mesh
      coupledPins off `shouldBe` coupledPins f
      closedHinges (coupledReference off) `shouldBe` closedHinges ref
      length springs `shouldBe` 6 * w
      sum (map hingeStiffness springs) `shouldBe` 24
      sum [hingeStiffness h | h <- closedHinges ref, SurfaceCrease _ <- [hingeRole h]] `shouldBe` 1
      forM_ springs $ \h -> do
        let (a, b, _, _) = hingeVertices h
        pa <- maybe (fail "missing control end") pure (IM.lookup a vertices)
        pb <- maybe (fail "missing control end") pure (IM.lookup b vertices)
        materialU pa `shouldBe` materialU pb
        materialU pa `shouldSatisfy` (`elem` [-0.125, -0.25, -0.375])
        hingeStiffness h `shouldBe` 8 * abs (materialV pa - materialV pb)
        (angle, _) <- right (hingeAngle h vertices)
        hingeRest h `shouldBe` 2 * angle
      forM_ (zip [0 ..] (samples mesh)) $ \(i, p) ->
        IM.member i (coupledPins f) `shouldBe` (abs (materialU p) <= 0.125 || abs (materialU p) == 0.5)

  it "retains original fixtures at width one and rejects invalid widths" $ do
    forM_ [1, 2] $ \n -> do
      a <- right (unequalCrease n UpperCurl)
      b <- right (unequalCreaseWithWidth n 1 UpperCurl)
      coupledSeed a `shouldBe` coupledSeed b
      closedHinges (coupledReference a) `shouldBe` closedHinges (coupledReference b)
    forM_ [0, 9] $ \w -> unequalCreaseWithWidth 1 w UpperCurl `shouldSatisfy` isLeft

  it "opens a gap while preserving the closed crease and material checks" $ do
    (f, r) <- solved 1 OpenUpperGrip
    audit <- endpoint f r
    pairMaximum audit `shouldSatisfy` (> 0.02)

  it "changes the lower response through contact, not a change to its controls" $ do
    (_, baseline) <- solved 1 MatchedHolds
    (f, curl) <- solved 1 UpperCurl
    _ <- endpoint f curl
    (offFixture, off) <- solved 1 CurlWithoutContact
    inequalityConverged off `shouldBe` True
    (lowerIndependent, _) <- right (panelChanges (inequalityMesh baseline) (inequalityMesh off))
    lowerIndependent `shouldSatisfy` (< 1e-7)
    (lowerContact, _) <- right (panelChanges (inequalityMesh off) (inequalityMesh curl))
    lowerContact `shouldSatisfy` (> 1e-4)
    gaps <- right (auditPairContact (closedOwners (coupledReference offFixture)) (inequalityMesh off))
    pairMinimum gaps `shouldSatisfy` (< -(1 / 100000))
    commonLift (inequalityInitial off) `shouldBe` 0
    forM_ (inequalitySteps off) $ \s -> stepLift s `shouldBe` 0

  it "retains separation and full endpoint checks on the finer curl mesh" $ do
    (f, r) <- solved 2 UpperCurl
    audit <- endpoint f r
    pairMaximum audit `shouldSatisfy` (> 0.001)

  it "checks a width-refined solve without welding its touching material" $ do
    f <- right (unequalCreaseWithWidth 1 2 UpperCurl)
    r <- right (solveCoupled (Settings 40 1e-5) f)
    audit <- endpoint f r
    pairMaximum audit `shouldSatisfy` (> 0)
    pairMaximum audit `shouldSatisfy` (< 1 / 1000000)
    let mesh = inequalityMesh r
    length (closedRoot (coupledReference f)) `shouldBe` 5
    componentCount mesh `shouldBe` 1

  it "refuses contradictory holds and comparisons with missing material" $ do
    forM_ [1, 2] $ \n -> do
      f <- right (unequalCrease n CrossedHolds)
      solveCoupled (Settings 40 1e-5) f `shouldSatisfy` isLeft
    f <- right (unequalCrease 1 MatchedHolds)
    let mesh = coupledSeed f
    panelChanges mesh mesh {samples = drop 1 (samples mesh)} `shouldSatisfy` isLeft
    unequalCrease 0 MatchedHolds `shouldSatisfy` isLeft

solved :: Int -> UnequalControl -> IO (CoupledFixture, InequalityResult)
solved n c = do
  f <- right (unequalCrease n c)
  r <- right (solveCoupledWith (unequalContactMode c) (Settings 40 1e-5) f)
  pure (f, r)

endpoint :: CoupledFixture -> InequalityResult -> IO PairAudit
endpoint f r = do
  let mesh = inequalityMesh r
      ref = coupledReference f
      vertices = IM.fromList (zip [0 ..] (samples mesh))
  inequalityConverged r `shouldBe` True
  checkCoupledMaterial f mesh `shouldBe` Right ()
  maxLengthError mesh `shouldSatisfy` (<= 1e-5)
  audit <- right (auditPairContact (closedOwners ref) mesh)
  pairMinimum audit `shouldBe` 0
  forM_ [h | h <- closedHinges ref, SurfaceCrease _ <- [hingeRole h]] $ \h -> do
    (angle, _) <- right (hingeAngle h vertices)
    abs (angleError angle pi) `shouldSatisfy` (< 1e-12)
  contact <- right (checkTriangleContact (V3 0 0 1) [(FaceId 0, FaceId 1)] (closedOwners ref) mesh)
  contactPassed contact `shouldBe` True
  exported <- right (coupledSurface f mesh)
  surfaceSamples exported `shouldBe` samples mesh
  forM_ (inequalitySteps r) $ \s -> do
    stepMinGap s `shouldSatisfy` (>= 0)
    when (stepAccepted s) $ stepEnergyAfter s `shouldSatisfy` (< stepEnergyBefore s)
  case reverse (inequalitySteps r) of
    [] -> expectationFailure "missing solver report"
    s : _ -> do
      stepSettled s `shouldBe` True
      stepMovement s `shouldSatisfy` (<= 1e-7)
      quadraticConverged (stepQuadratic s) `shouldBe` True
  pure audit

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
