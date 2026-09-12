module ContactDiscoverySpec (spec) where

import ContactDiscovery
import ContactExample
import Control.Monad (forM_)
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.List (sort)
import FoldBending (Hinge (..), HingeRole (..), hingeAngle)
import FoldContact (ContactRow (..), contactTolerance)
import FoldMaterial (componentCount)
import FoldRelaxation
import PanelContact (checkTriangleContact, contactPassed)
import Senbazuru.Fold.Types (EdgeId (..), FaceId (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import SurfaceContact qualified as Contact
import Test.Hspec

spec :: Spec
spec = describe "reference-pose contact discovery" $ do
  it "finds the opposing-flap orders and reproduces the authored correction" $ do
    fixture <- right (opposingFlapsAt 1 145 125)
    let refined = exampleRefined fixture
        mesh = refinedMesh refined
        hinges = exampleHinges fixture
    (direction, orders) <- maybe (fail "missing independent order oracle") pure (surfaceLayerRequirements (exampleSurface fixture))
    reference <- right (discoverReference (exampleClearance fixture) direction (refinedPanels refined) mesh)
    sort (referenceOrders reference) `shouldBe` sort orders
    manual <- right (relaxSurfaceContact defaultSettings hinges (exampleContact fixture) mesh)
    discovered <- right (relaxDiscoveredContact defaultSettings hinges reference mesh)
    final <- finalMesh discovered
    manualMesh <- finalMesh manual
    converged discovered `shouldBe` True
    final `shouldBe` manualMesh
    report <- right (checkTriangleContact direction orders (refinedPanels refined) final)
    contactPassed report `shouldBe` True
    maxLengthError final `shouldSatisfy` (<= lengthTolerance defaultSettings)
    forM_ (checkpoints discovered) $ \point -> do
      let current = checkpointMesh point
      triangles current `shouldBe` triangles mesh
      map sampleMaterial (samples current) `shouldBe` map sampleMaterial (samples mesh)
      componentCount current `shouldBe` 1
    rows <- right (discoveredContacts reference final)
    minimum (0 : map contactGap rows) `shouldSatisfy` (>= negate contactTolerance)

  it "keeps reference order when later geometry crosses instead of accepting a swapped order" $ do
    reference <- right (discoverReference 0 axis owners separated)
    let crossed = mapIndexed (\i (V3 x y z) -> V3 x y (if i == 4 then -0.2 else z)) separated
    rows <- right (discoveredContacts reference crossed)
    minimum (0 : map contactGap rows) `shouldSatisfy` (< (-0.1))
    discoverReference 0 axis owners crossed `shouldBe` Left (CrossedReferencePanels (FaceId 0) (FaceId 1))
    referenceOrders reference `shouldBe` [(FaceId 0, FaceId 1)]

  it "refuses coplanar reference overlap even when the coincident corners have different ids" $ do
    let coplanar = mapIndexed (\_ (V3 x y _) -> V3 x y 0) separated
    discoverReference 0 axis owners coplanar `shouldBe` Left (AmbiguousReferenceOrder (FaceId 0) (FaceId 1))

  it "ignores mere shared boundaries when discovering reference order" $ do
    let joined = Mesh [Sample (V2 x y) (V3 x y 0) | (x, y) <- [(0, 0), (1, 0), (1, 1), (0, 1)]] [(0, 1, 2), (0, 2, 3)]
    reference <- right (discoverReference 1e-6 axis owners joined)
    referenceOrders reference `shouldBe` []
    referenceCandidates reference `shouldBe` []

  it "does not treat overlapping bounding boxes as an actual triangle overlap" $ do
    let trianglesOnly = makeMesh [V3 0 0 0, V3 2 0 0, V3 0 2 0, V3 2 2 1, V3 2 1.5 1, V3 1.5 2 1]
    reference <- right (discoverReference 0 axis owners trianglesOnly)
    referenceCandidates reference `shouldBe` []

  it "discovers moving edge intersections even when no original corner is inside the partner" $ do
    let edgesCross = makeMesh [V3 (-2) (-1) 0, V3 2 (-1) 0, V3 0 2 0, V3 (-2) 1 0.4, V3 2 1 0.4, V3 0 (-2) 0.4]
    reference <- right (discoverReference 0 axis owners edgesCross)
    referenceOrders reference `shouldBe` [(FaceId 0, FaceId 1)]
    length (referenceCandidates reference) `shouldBe` 1

  it "discovers an upright flap using its 3D area and both endpoint heights" $ do
    let upright = makeMesh [V3 (-2) (-2) 0, V3 2 (-2) 0, V3 0 3 0, V3 0 0 0.2, V3 0 0 0.6, V3 0 1 0.6]
    reference <- right (discoverReference 0 axis owners upright)
    referenceOrders reference `shouldBe` [(FaceId 0, FaceId 1)]
    map Contact.candidateGapRange (referenceCandidates reference) `shouldBe` [Just (0.2, 0.6)]

  it "refuses potentially overlapping upright pairs when neither supplies a height" $ do
    let upright = makeMesh [V3 0 0 0, V3 0 1 0, V3 0 0 1, V3 0 0 2, V3 0 1 2, V3 0 0 3]
    discoverReference 0 axis owners upright `shouldBe` Left (UncheckableReferenceOrder (FaceId 0) (FaceId 1))

  it "rescans later overlaps and refuses pairs missing from the reference" $ do
    let apart = makeMesh (triangleAt 0 0 ++ triangleAt 2 1)
        together = mapIndexed (\i p -> if i >= 3 then p ^-^ V3 1.5 0 0 else p) apart
    reference <- right (discoverReference 0 axis owners apart)
    referenceOrders reference `shouldBe` []
    discoveredContacts reference apart `shouldBe` Right []
    discoveredContacts reference together `shouldBe` Left (NewContactPair (FaceId 0) (FaceId 1))
    relaxDiscoveredContact defaultSettings [] reference together `shouldBe` Left (ContactDiscoveryFailure (NewContactPair (FaceId 0) (FaceId 1)))

  it "accepts a new overlap whose order follows transitively from the reference" $ do
    let initial = (makeMesh (triangleAt 0 0 ++ triangleAt 0.7 1 ++ triangleAt 1.4 2)) {triangles = [(0, 1, 2), (3, 4, 5), (6, 7, 8)]}
        together = mapIndexed (\i p -> if i >= 6 then p ^-^ V3 1.3 0 0 else p) initial
    reference <- right (discoverReference 0 axis [FaceId 0, FaceId 1, FaceId 2] initial)
    referenceOrders reference `shouldBe` [(FaceId 0, FaceId 1), (FaceId 1, FaceId 2)]
    rows <- right (discoveredContacts reference together)
    rows `shouldSatisfy` (not . null)
    minimum (0 : map contactGap rows) `shouldSatisfy` (>= 0)

  it "uses geometry rather than panel ids or triangle winding to choose order" $ do
    let reversed = separated {triangles = [(2, 1, 0), (5, 4, 3)]}
    reference <- right (discoverReference 0 axis [FaceId 9, FaceId 3] reversed)
    referenceOrders reference `shouldBe` [(FaceId 9, FaceId 3)]

  it "keeps discovery invariant when positions and the direction rotate together" $ do
    let rotate (V3 x y z) = V3 z x y
        moved = mapIndexed (\_ p -> rotate p ^+^ V3 3 (-2) 5) separated
    reference <- right (discoverReference 0 axis owners separated)
    rotated <- right (discoverReference 0 (rotate axis) owners moved)
    referenceOrders rotated `shouldBe` referenceOrders reference
    map Contact.candidatePanels (referenceCandidates rotated) `shouldBe` map Contact.candidatePanels (referenceCandidates reference)

  it "refuses ownership or material changes and invalid preparation inputs" $ do
    discoverReference (-1) axis owners separated `shouldBe` Left (DiscoveryGeometry Contact.InvalidContactClearance)
    discoverReference 0 (V3 0 0 0) owners separated `shouldBe` Left (DiscoveryGeometry Contact.InvalidContactDirection)
    discoverReference 0 axis [] separated `shouldBe` Left (DiscoveryGeometry Contact.InvalidContactOwners)
    reference <- right (discoverReference 0 axis owners separated)
    discoveredContacts reference separated {triangles = reverse (triangles separated)} `shouldBe` Left (DiscoveryGeometry Contact.ChangedContactMaterial)

  it "does not call an exhausted discovered-contact solve converged" $ do
    fixture <- right (opposingFlapsAt 1 145 125)
    let refined = exampleRefined fixture
        mesh = refinedMesh refined
    reference <- right (discoverReference (exampleClearance fixture) axis (refinedPanels refined) mesh)
    result <- right (relaxDiscoveredContact defaultSettings {iterationLimit = 1} (exampleHinges fixture) reference mesh)
    converged result `shouldBe` False

  describe "sampled first-contact history" $ do
    it "learns the previously absent flap order during an angle-defined approach" $ do
      poses <- right (opposingApproach 1)
      map approachAngles poses `shouldBe` [(145, 105), (145, 110), (145, 115), (145, 120), (145, 121)]
      map (length . referenceOrders . approachHistory) poses `shouldBe` [2, 2, 2, 2, 3]
      firstPose <- case poses of p : _ -> pure p; [] -> fail "no approach"
      lastPose <- case reverse poses of p : _ -> pure p; [] -> fail "no approach"
      let initial = refinedMesh (exampleRefined (approachExample firstPose))
          fixture = approachExample lastPose
          refined = exampleRefined fixture
          mesh = refinedMesh refined
          learned = approachHistory lastPose
      referenceOrders (approachHistory firstPose) `shouldNotContain` [(FaceId 0, FaceId 2)]
      map observationNewOrders (drop 1 (referenceObservations learned)) `shouldBe` [[], [], [], [(FaceId 0, FaceId 2)]]
      map observationNumber (referenceObservations learned) `shouldBe` [0 .. 4]
      forM_ poses $ \pose -> do
        let current = refinedMesh (exampleRefined (approachExample pose))
        triangles current `shouldBe` triangles initial
        map sampleMaterial (samples current) `shouldBe` map sampleMaterial (samples initial)
        componentCount current `shouldBe` 1
        maxLengthError current `shouldSatisfy` (< 1e-12)
        let vertices = IM.fromList (zip [0 ..] (samples current))
            (leftAngle, rightAngle) = approachAngles pose
        forM_ (exampleHinges (approachExample pose)) $ \hinge -> do
          (angle, _) <- right (hingeAngle hinge vertices)
          let expected = case hingeRole hinge of
                SurfaceCrease (EdgeId 8) -> leftAngle
                SurfaceCrease (EdgeId 9) -> rightAngle
                _ -> 0
          abs (angle * 180 / pi - expected) `shouldSatisfy` (< 1e-10)
        report <- right (checkTriangleContact axis (referenceOrders (approachHistory pose)) (refinedPanels refined) current)
        contactPassed report `shouldBe` True
      corrected <- right (relaxDiscoveredContact defaultSettings (exampleHinges fixture) learned mesh)
      authored <- right (relaxSurfaceContact defaultSettings (exampleHinges fixture) (exampleContact fixture) mesh)
      final <- finalMesh corrected
      manual <- finalMesh authored
      converged corrected `shouldBe` True
      final `shouldBe` manual
      report <- right (checkTriangleContact axis (referenceOrders learned) (refinedPanels refined) final)
      contactPassed report `shouldBe` True
      maxLengthError final `shouldSatisfy` (<= lengthTolerance defaultSettings)
      forM_ (checkpoints corrected) $ \point -> do
        triangles (checkpointMesh point) `shouldBe` triangles initial
        map sampleMaterial (samples (checkpointMesh point)) `shouldBe` map sampleMaterial (samples initial)
        componentCount (checkpointMesh point) `shouldBe` 1

    it "remembers the first side through separation and refuses reversed re-contact" $ do
      let apart = makeMesh (triangleAt 0 0 ++ triangleAt 2 1)
          together = mapIndexed (\i p -> if i >= 3 then p ^-^ V3 1.5 0 0 else p) apart
          reversed = mapIndexed (\i p -> if i >= 3 then p ^-^ V3 0 0 2 else p) together
      reference <- right (discoverReference 0 axis owners apart)
      learned <- right (observeContactPose reference together)
      withdrawn <- right (observeContactPose learned apart)
      referenceOrders withdrawn `shouldBe` [(FaceId 0, FaceId 1)]
      length (referenceObservations withdrawn) `shouldBe` 3
      observeContactPose withdrawn reversed `shouldSatisfy` isLeft
      again <- right (observeContactPose withdrawn together)
      map observationNewOrders (referenceObservations again) `shouldBe` [[], [(FaceId 0, FaceId 1)], [], []]
      referenceOrders reference `shouldBe` []
      length (referenceObservations withdrawn) `shouldBe` 3
      -- A failed observation cannot change the frozen solver constraints either.
      rows <- right (discoveredContacts withdrawn reversed)
      minimum (0 : map contactGap rows) `shouldSatisfy` (< (-0.9))

    it "learns the opposite first-encounter side from geometry" $ do
      let apart = makeMesh (triangleAt 0 0 ++ triangleAt 2 (-1))
          together = mapIndexed (\i p -> if i >= 3 then p ^-^ V3 1.5 0 0 else p) apart
      reference <- right (discoverReference 0 axis owners apart)
      learned <- right (observeContactPose reference together)
      referenceOrders learned `shouldBe` [(FaceId 1, FaceId 0)]

    it "refuses a crossed or ambiguous first encounter without recording it" $ do
      let apart = mapIndexed (\i p -> if i >= 3 then p ^+^ V3 5 0 0 else p) separated
          crossed = mapIndexed (\i (V3 x y z) -> V3 x y (if i == 4 then -0.2 else z)) separated
          coplanar = mapIndexed (\_ (V3 x y _) -> V3 x y 0) separated
      reference <- right (discoverReference 0 axis owners apart)
      observeContactPose reference crossed `shouldBe` Left (CrossedReferencePanels (FaceId 0) (FaceId 1))
      observeContactPose reference coplanar `shouldBe` Left (AmbiguousReferenceOrder (FaceId 0) (FaceId 1))
      referenceOrders reference `shouldBe` []
      length (referenceObservations reference) `shouldBe` 1
      learned <- right (observeContactPose reference separated)
      length (referenceObservations learned) `shouldBe` 2

    it "refuses a new encounter with insufficient numerical clearance" $ do
      let apart = makeMesh (triangleAt 0 0 ++ triangleAt 2 1e-5)
          close = mapIndexed (\i p -> if i >= 3 then p ^-^ V3 1.5 0 0 else p) apart
      reference <- right (discoverReference 1e-4 axis owners apart)
      observeContactPose reference close `shouldSatisfy` isLeft
      referenceOrders reference `shouldBe` []

    it "refuses uncheckable first encounters and changed original-sheet coordinates" $ do
      let upright = makeMesh [V3 0 0 0, V3 0 1 0, V3 0 0 1, V3 0 0 2, V3 0 1 2, V3 0 0 3]
          apart = mapIndexed (\i p -> if i >= 3 then p ^+^ V3 2 0 0 else p) upright
      reference <- right (discoverReference 0 axis owners apart)
      observeContactPose reference upright `shouldBe` Left (UncheckableReferenceOrder (FaceId 0) (FaceId 1))
      let remapped = apart {samples = [s {sampleMaterial = V2 9 9} | s <- samples apart]}
      observeContactPose reference remapped `shouldBe` Left (DiscoveryGeometry Contact.ChangedContactMaterial)

    it "does not overwrite a transitive order when the pair first overlaps" $ do
      let initial = (makeMesh (triangleAt 0 0 ++ triangleAt 0.7 1 ++ triangleAt 1.4 2)) {triangles = [(0, 1, 2), (3, 4, 5), (6, 7, 8)]}
          together = mapIndexed (\i p -> if i >= 6 then p ^-^ V3 1.3 0 0 else p) initial
      reference <- right (discoverReference 0 axis [FaceId 0, FaceId 1, FaceId 2] initial)
      learned <- right (observeContactPose reference together)
      referenceOrders learned `shouldBe` referenceOrders reference
      map observationNewOrders (drop 1 (referenceObservations learned)) `shouldBe` [[]]

    it "checks material identity and independent triangle crossings before accepting a pose" $ do
      reference <- right (discoverReference 0 axis owners separated)
      observeContactPose reference separated {triangles = reverse (triangles separated)} `shouldBe` Left (DiscoveryGeometry Contact.ChangedContactMaterial)
      -- Same source panel: directional discovery has no partner, but the
      -- independent observation check must still reject its self-crossing.
      let crossed = mapIndexed (\i (V3 x y z) -> V3 x y (if i == 4 then -0.2 else z)) separated
          samePanel = [FaceId 0, FaceId 0]
      one <- right (discoverReference 0 axis samePanel separated)
      observeContactPose one crossed `shouldSatisfy` isLeft

axis :: V3
axis = V3 0 0 1

owners :: [FaceId]
owners = [FaceId 0, FaceId 1]

separated :: MaterialMesh
separated = makeMesh [V3 (-2) (-2) 0, V3 2 (-2) 0, V3 0 3 0, V3 (-0.3) 0 0.2, V3 0.3 0 0.2, V3 0 0.6 0.2]

makeMesh :: [V3] -> MaterialMesh
makeMesh points = Mesh (zipWith Sample (cycle [V2 0 0, V2 1 0, V2 0 1]) points) [(0, 1, 2), (3, 4, 5)]

triangleAt :: Double -> Double -> [V3]
triangleAt x z = [V3 x 0 z, V3 (x + 1.2) 0 z, V3 x 1 z]

mapIndexed :: (Int -> V3 -> V3) -> MaterialMesh -> MaterialMesh
mapIndexed f mesh = mesh {samples = [s {position = f i (position s)} | (i, s) <- zip [0 ..] (samples mesh)]}

finalMesh :: Relaxation -> IO MaterialMesh
finalMesh result = case reverse (checkpoints result) of
  point : _ -> pure (checkpointMesh point)
  [] -> fail "no final checkpoint"

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
