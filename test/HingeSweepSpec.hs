module HingeSweepSpec (spec) where

import ContactDiscovery
import ContactExample
import Control.Monad (forM_)
import Data.Either (isLeft)
import FlapExample (singleFlap)
import FoldRelaxation (maxLengthError)
import Senbazuru.Fold.Types (Frame (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..), cross)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact (checkLocalTriangleContact, checkTriangleContact, contactPassed)
import Senbazuru.Origami.Folding (foldFrameWith)
import Senbazuru.Origami.HingeSweep
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

  it "checks a flat endpoint without weakening the strict caller's contact policy" $ do
    folded <- right (foldFrameWith singleFlap {edgesFoldAngle = replicate 7 0})
    sheet <- right (surfaceFromFolded folded)
    (mesh, _) <- right (refineSurface 0 sheet)
    -- A general proper rotation, not just a permutation of coordinate axes.
    let axis = (1 / sqrt 14) *^ V3 1 2 3
        rotate p = cos 0.7 *^ p ^+^ sin 0.7 *^ cross axis p ^+^ ((1 - cos 0.7) * dot axis p) *^ axis
        move p = rotate p ^+^ V3 3 (-2) 5
        moved = mesh {samples = [s {position = move (position s)} | s <- samples mesh]}
    sweep <- right (prepareSweep (move (V3 0.5 0 0)) (rotate (V3 0 1 0)) (-pi) [1, 2, 3, 4] moved)
    strict <- right (checkSweep defaultSweepSettings sweep)
    sweepOutcome strict `shouldNotBe` SweepClear
    accepted <- right (checkSweepWithFlatEndpoints defaultSweepSettings sweep)
    sweepOutcome accepted `shouldBe` SweepClear
    sweepEndpointContacts accepted `shouldSatisfy` (not . null)
    map contactProgress (sweepEndpointContacts accepted) `shouldSatisfy` all (== 1)
    map contactSide (sweepEndpointContacts accepted) `shouldSatisfy` all (== 1)
    -- Check interiors independently with the ordinary static contact test.
    forM_ [0.01, 0.02 .. 0.99] $ \t -> do
      current <- right (sweepMeshAt sweep t)
      report <- right (checkLocalTriangleContact (V3 0 0 1) [] current)
      contactPassed report `shouldBe` True

  it "does not excuse a separate hinge seam or an axis outside the fixed plane" $ do
    let mesh = Mesh [Sample (V2 x y) (V3 x y z) | (x, y, z) <- [(0, 0, 0), (-1, 0, 0), (0, 1, 0), (0, 0, 0), (1, 0, 0), (0, 1, 0)]] [(0, 1, 2), (3, 4, 5)]
    detached <- right (prepareSweep (V3 0 0 0) (V3 0 1 0) pi [3, 4, 5] mesh)
    result <- right (checkSweepWithFlatEndpoints defaultSweepSettings detached)
    sweepOutcome result `shouldNotBe` SweepClear
    let shifted = mesh {samples = [s {position = position s ^+^ V3 0 0 (if i < 3 then 1e-8 else 0)} | (i, s) <- zip [0 :: Int ..] (samples mesh)]}
    offPlane <- right (prepareSweep (V3 0 0 0) (V3 0 1 0) (-pi) [3, 4, 5] shifted)
    refused <- right (checkSweepWithFlatEndpoints defaultSweepSettings offPlane)
    sweepOutcome refused `shouldNotBe` SweepClear

  it "retains only declared coplanar contacts whose relative motion is constant" $ do
    let points = [V3 1 0 0, V3 2 0 0, V3 1 1 0]
        mesh = Mesh [Sample (V2 x y) p | p@(V3 x y _) <- points ++ points] [(0, 1, 2), (3, 4, 5)]
    forM_ [[], [0 .. 5]] $ \moving -> do
      sweep <- right (prepareSweep (V3 0 0 0) (V3 0 1 0) pi moving mesh)
      strict <- right (checkSweepWithFlatEndpoints defaultSweepSettings sweep)
      sweepOutcome strict `shouldBe` SweepCollision 0 [(0, 1)]
      result <- right (checkSweepWithRigidContacts defaultSweepSettings [(1, 0)] sweep)
      sweepOutcome result `shouldBe` SweepClear
      forM_ [0, 0.5, 1] $ \t -> do
        current <- right (sweepMeshAt sweep t)
        let normalAt = case samples current of
              a : b : c : _ -> cross (position b ^-^ position a) (position c ^-^ position a)
              _ -> V3 0 0 1
        report <- right (checkLocalTriangleContact normalAt [(0, 1)] current)
        contactPassed report `shouldBe` True
      forM_ [[(-1, 1)], [(0, 2)], [(0, 0)]] $ \pairs ->
        checkSweepWithRigidContacts defaultSweepSettings pairs sweep `shouldSatisfy` isLeft
    differing <- right (prepareSweep (V3 0 0 0) (V3 0 1 0) pi [0 .. 2] mesh)
    checkSweepWithRigidContacts defaultSweepSettings [(0, 1)] differing `shouldBe` Left (InvalidRigidContact 0 1)
    let separated = mesh {samples = [s {position = position s ^+^ V3 0 0 (if i < 3 then 0 else 1e-8)} | (i, s) <- zip [0 :: Int ..] (samples mesh)]}
    separatedSweep <- right (prepareSweep (V3 0 0 0) (V3 0 1 0) pi [0 .. 5] separated)
    checkSweepWithRigidContacts defaultSweepSettings [(0, 1)] separatedSweep `shouldBe` Left (InvalidRigidContact 0 1)

  it "does not hide a constant crossing behind another pair's rigid contact" $ do
    let points = [V3 (-2) (-2) 0, V3 2 (-2) 0, V3 0 3 0]
        other = [V3 0 0 (-1), V3 0 1 1, V3 1 0 0]
        mesh = Mesh [Sample (V2 x y) p | p@(V3 x y _) <- points ++ points ++ other] [(0, 1, 2), (3, 4, 5), (6, 7, 8)]
    sweep <- right (prepareSweep (V3 0 0 5) (V3 0 1 0) 0 [] mesh)
    result <- right (checkSweepWithRigidContacts defaultSweepSettings [(0, 1)] sweep)
    case sweepOutcome result of
      SweepCollision 0 pairs -> pairs `shouldContain` [(0, 2), (1, 2)]
      otherResult -> expectationFailure (show otherResult)
    checkSweepWithRigidContacts defaultSweepSettings [(0, 2)] sweep `shouldBe` Left (InvalidRigidContact 0 2)

  it "lifts a flap whose hinge rests across another panel's interior" $ do
    let ps = [V3 (-2) (-2) 0, V3 2 (-2) 0, V3 0 3 0, V3 0 0 0, V3 1 0 0, V3 0 1 0]
        mesh = Mesh [Sample (V2 x y) p | p@(V3 x y _) <- ps] [(0, 1, 2), (3, 4, 5)]
    forM_ [pi / 2, negate (pi / 2)] $ \angle -> do
      sweep <- right (prepareSweep (V3 0 0 0) (V3 0 1 0) angle [3, 4, 5] mesh)
      strict <- right (checkSweepWithRigidContacts defaultSweepSettings [] sweep)
      sweepOutcome strict `shouldNotBe` SweepClear
      result <- right (checkSweepWithLayerContacts defaultSweepSettings [] [(0, 1)] sweep)
      sweepOutcome result `shouldBe` SweepClear
      sweepEndpointContacts result `shouldBe` [EndpointContact 0 0 1 (if angle > 0 then -1 else 1)]
      forM_ [0.01, 0.25, 0.5, 0.75, 1] $ \t -> do
        current <- right (sweepMeshAt sweep t)
        report <- right (checkLocalTriangleContact (V3 0 0 1) [] current)
        contactPassed report `shouldBe` True
      forM_ [[(0, 0)], [(0, 2)], [(-1, 1)]] $ \pairs ->
        checkSweepWithLayerContacts defaultSweepSettings [] pairs sweep `shouldSatisfy` isLeft
    -- Naming contact cannot hide a full revolution, an initial gap or a
    -- nearly hinged corner fixed on the wrong side by preparation's tolerance.
    full <- right (prepareSweep (V3 0 0 0) (V3 0 1 0) (2 * pi) [3, 4, 5] mesh)
    result <- right (checkSweepWithLayerContacts defaultSweepSettings [] [(0, 1)] full)
    sweepOutcome result `shouldNotBe` SweepClear
    forM_ [1e-13, -1e-13] $ \offset -> do
      let shifted = mesh {samples = [s {position = position s ^+^ (if i `elem` [3, 5] then V3 offset 0 0 else V3 0 0 0)} | (i, s) <- zip [0 :: Int ..] (samples mesh)]}
      sweep <- right (prepareSweep (V3 0 0 0) (V3 0 1 0) (pi / 2) [3, 4, 5] shifted)
      report <- right (checkSweepWithLayerContacts defaultSweepSettings [] [(0, 1)] sweep)
      sweepOutcome report `shouldNotBe` SweepClear
    let raised = mesh {samples = [s {position = position s ^+^ (if i >= 3 then V3 0 0 1e-8 else V3 0 0 0)} | (i, s) <- zip [0 :: Int ..] (samples mesh)]}
    offPlane <- right (prepareSweep (V3 0 0 0) (V3 0 1 0) (pi / 2) [3, 4, 5] raised)
    checkSweepWithLayerContacts defaultSweepSettings [] [(0, 1)] offPlane `shouldBe` Left (InvalidRestingContact 0 1)

  it "supports a free hinge edge only through its declared touching partner" $ do
    forM_ [0, pi / 6] $ \from -> forM_ [False, True] $ \transformed -> do
      let mesh = hingeStack from
          axis = (1 / sqrt 14) *^ V3 1 2 3
          rotate p = cos 0.7 *^ p ^+^ sin 0.7 *^ cross axis p ^+^ ((1 - cos 0.7) * dot axis p) *^ axis
          turn = if transformed then rotate else id
          move p = turn p ^+^ (if transformed then V3 3 (-2) 5 else V3 0 0 0)
          moved = mesh {samples = [s {position = move (position s)} | s <- samples mesh]}
      sweep <- right (prepareSweep (move (V3 0 0 0)) (turn (V3 0 1 0)) (pi / 3) [0, 2, 3, 4, 5, 6] moved)
      accepted <- right (checkSweepWithRigidContacts defaultSweepSettings [(1, 2)] sweep)
      sweepOutcome accepted `shouldBe` SweepClear
      -- The bare seam still has no authorizing stack, and the old callers
      -- must retain their strict policy even on this otherwise legal motion.
      forM_ [checkSweep, checkSweepWithFlatEndpoints, (`checkSweepWithRigidContacts` [])] $ \check -> do
        strict <- right (check defaultSweepSettings sweep)
        sweepOutcome strict `shouldNotBe` SweepClear
      forM_ [0, 0.25, 0.5, 0.75, 1] $ \t -> do
        current <- right (sweepMeshAt sweep t)
        triangles current `shouldBe` triangles mesh
        length (samples current) `shouldBe` 7
        let n = turn (V3 (sin (from + t * pi / 3)) 0 (cos (from + t * pi / 3)))
        report <- right (checkLocalTriangleContact n [(1, 2)] current)
        contactPassed report `shouldBe` True

  it "does not let a shared corner support a longer free hinge edge" $ do
    let mesh = hingeStack 0
        -- The partner meets the hinge only at one shared corner. Its other
        -- corners are off the hinge, so it alone is a legal turning triangle.
        cornerOnly = mesh {samples = samples mesh ++ [Sample (V2 1 1) (V3 1 1 0)], triangles = [(0, 1, 2), (0, 3, 7), (4, 5, 6)]}
    support <- right (prepareSweep (V3 0 0 0) (V3 0 1 0) (pi / 3) [0, 2, 3, 7] cornerOnly {triangles = [(0, 1, 2), (0, 3, 7)]})
    supportCheck <- right (checkSweepWithFlatEndpoints defaultSweepSettings support)
    sweepOutcome supportCheck `shouldBe` SweepClear
    sweep <- right (prepareSweep (V3 0 0 0) (V3 0 1 0) (pi / 3) [0, 2, 3, 4, 5, 6, 7] cornerOnly)
    result <- right (checkSweepWithRigidContacts defaultSweepSettings [(1, 2)] sweep)
    sweepOutcome result `shouldNotBe` SweepClear

  it "refuses nearly hinged free corners outside the contact roundoff allowance" $ do
    forM_ [-1e-13, 1e-13] $ \offset -> do
      let mesh = hingeStack 0
          moved = mesh {samples = [s {position = position s ^+^ (if i `elem` [4, 6] then V3 offset 0 0 else V3 0 0 0)} | (i, s) <- zip [0 :: Int ..] (samples mesh)]}
      sweep <- right (prepareSweep (V3 0 0 0) (V3 0 1 0) (pi / 3) [0, 2, 3, 4, 5, 6] moved)
      result <- right (checkSweepWithRigidContacts defaultSweepSettings [(1, 2)] sweep)
      sweepOutcome result `shouldNotBe` SweepClear

  it "checks the whole route of a stack with a free hinge edge" $ do
    sweep <- right (prepareSweep (V3 0 0 0) (V3 0 1 0) (2 * pi) [0, 2, 3, 4, 5, 6] (hingeStack (pi / 6)))
    result <- right (checkSweepWithRigidContacts defaultSweepSettings [(1, 2)] sweep)
    sweepOutcome result `shouldNotBe` SweepClear

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

-- Fixed left triangle, a right triangle joined at ids 0/2, then a touching
-- copy with a distinct free edge (ids 4/6) in exactly the same hinge positions.
hingeStack :: Double -> MaterialMesh
hingeStack angle = Mesh [Sample (V2 x y) p | p@(V3 x y _) <- ps] [(0, 1, 2), (0, 3, 2), (4, 5, 6)]
  where
    ps = [V3 0 0 0, V3 (-1) 0 0, V3 0 1 0, V3 (cos angle) 0 (negate (sin angle)), V3 0 0 0, V3 (cos angle) 0 (negate (sin angle)), V3 0 1 0]

rightIds :: MaterialMesh -> [Int]
rightIds mesh = [i | (i, s) <- zip [0 ..] (samples mesh), let V2 u _ = sampleMaterial s, u >= 0.7]

rightSweep :: MaterialMesh -> Double -> Either SweepError HingeSweep
rightSweep mesh angle = prepareSweep (V3 0.7 0 0) (V3 0 (-1) 0) (angle * pi / 180) (rightIds mesh) mesh

maximumDifference :: MaterialMesh -> MaterialMesh -> Double
maximumDifference a b = maximum (0 : zipWith (\x y -> norm (position x ^-^ position y)) (samples a) (samples b))

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
