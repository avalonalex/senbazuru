module LocalContactDiscoverySpec (spec) where

import Control.Monad (foldM, forM_)
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.List (sort)
import FoldBending (Hinge (..), hingeAngle)
import FoldContact (ContactRow (..), contactTolerance)
import FoldMaterial (componentCount)
import FoldRelaxation
import LocalContactDiscovery
import PanelContact
import SelfContactExample
import Senbazuru.Fold.Types (FaceId (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import SurfaceContact qualified as Contact
import Test.Hspec

spec :: Spec
spec = describe "local contact discovery in bending paper" $ do
  forM_ [8] $ \count ->
    it ("discovers and corrects the curled strip with " ++ show count ++ " spans") $ do
      fixture <- right (curledPanelAt count (356 / fromIntegral count))
      let direction = V3 (-3) 0 1
      let mesh = curlMesh fixture
          hinges = curlHinges fixture
      -- Only geometry enters discovery. The fixture's authored pairs are not
      -- supplied, and every triangle still has the same source-panel owner.
      reference <- right (discoverLocalReference (curlClearance fixture) 0.03 direction mesh)
      length (localReferenceCandidates reference) `shouldBe` 3
      localReferenceOrders reference `shouldBe` [(0, 14), (0, 15), (1, 14), (1, 15)]
      curlOwners fixture `shouldBe` replicate (2 * count) (FaceId 0)
      result <- right (relaxLocalContact defaultSettings hinges reference mesh)
      final <- finalMesh result
      converged result `shouldBe` True
      report <- right (checkLocalTriangleContact direction (localReferenceOrders reference) final)
      contactPassed report `shouldBe` True
      checkedPanelPairs report `shouldBe` (2 * count * (2 * count - 1) `div` 2)
      maxLengthError final `shouldSatisfy` (< 1e-5)
      rows <- right (localDiscoveredContacts reference final)
      rows `shouldSatisfy` (not . null)
      minimum (map contactGap rows) `shouldSatisfy` (>= negate contactTolerance)
      minimum (map contactGap rows) `shouldSatisfy` (< 1e-5)
      forM_ (checkpoints result) $ \point -> do
        let current = checkpointMesh point
        triangles current `shouldBe` triangles mesh
        map sampleMaterial (samples current) `shouldBe` map sampleMaterial (samples mesh)
        componentCount current `shouldBe` 1
        localDiscoveredContacts reference current `shouldSatisfy` (not . isLeft)

  it "finds the finer strip's partners and refuses contacts missing from that reference" $ do
    fixture <- right (curledPanelAt 16 22.25)
    let mesh = curlMesh fixture
        direction = V3 (-3) 0 1
    reference <- right (discoverLocalReference (curlClearance fixture) 0.03 direction mesh)
    localReferenceOrders reference `shouldBe` [(0, 30), (0, 31), (1, 30), (1, 31)]
    -- The ordinary endpoint solve temporarily meets the neighboring spans.
    -- Its endpoint can be valid while this reference cannot cover its trials.
    model <- right (Contact.prepareTriangleContact (curlClearance fixture) direction (localReferenceOrders reference) mesh)
    authored <- right (relaxSurfaceContact defaultSettings (curlHinges fixture) model mesh)
    converged authored `shouldBe` True
    let uncovered = [err | point <- checkpoints authored, Left err <- [localDiscoveredContacts reference (checkpointMesh point)]]
    uncovered `shouldSatisfy` (not . null)
    forM_ uncovered $ \case
      NewLocalContactPair _ _ -> pure ()
      other -> expectationFailure (show other)
    final <- finalMesh authored
    report <- right (checkLocalTriangleContact direction (localReferenceOrders reference) final)
    contactPassed report `shouldBe` True
    maxLengthError final `shouldSatisfy` (< 1e-5)
    guarded <- right (relaxLocalContact defaultSettings (curlHinges fixture) reference mesh)
    converged guarded `shouldBe` False
    forM_ (checkpoints guarded) $ \point -> do
      triangles (checkpointMesh point) `shouldBe` triangles mesh
      localDiscoveredContacts reference (checkpointMesh point) `shouldSatisfy` (not . isLeft)

  it "does not exempt future self-contact inside one initially flat patch" $ do
    fixture <- right (curledPanel 8)
    let bent = curlMesh fixture
        flat = bent {samples = [sample {position = let V2 u v = sampleMaterial sample in V3 u v 0} | sample <- samples bent]}
    reference <- right (discoverLocalReference 1e-6 0.03 axis flat)
    localReferenceOrders reference `shouldBe` []
    free <- right (relaxHinges defaultSettings (curlHinges fixture) bent) >>= finalMesh
    case localDiscoveredContacts reference free of
      Left (NewLocalContactPair _ _) -> pure ()
      other -> expectationFailure (show other)

  it "keeps a learned order when the triangles later cross or swap sides" $ do
    reference <- right (discoverLocalReference 0 10 axis separated)
    localReferenceOrders reference `shouldBe` [(0, 1)]
    let crossed = move (\i (V3 x y z) -> V3 x y (if i == 4 then -0.2 else z)) separated
        swapped = move (\i p -> if i >= 3 then p ^-^ V3 0 0 1 else p) separated
    discoverLocalReference 0 10 axis crossed `shouldBe` Left (CrossedLocalReference 0 1)
    forM_ [crossed, swapped] $ \mesh -> do
      rows <- right (localDiscoveredContacts reference mesh)
      minimum (map contactGap rows) `shouldSatisfy` (< (-0.1))
    localReferenceOrders reference `shouldBe` [(0, 1)]

  it "refuses coplanar first contact even with coincident positions and distinct ids" $ do
    let flat = move (\_ (V3 x y _) -> V3 x y 0) separated
    discoverLocalReference 0 10 axis flat `shouldBe` Left (AmbiguousLocalOrder 0 1)
    let coincident = pairMesh (triangleAt 0 0 ++ triangleAt 0 0)
    discoverLocalReference 0 10 axis coincident `shouldBe` Left (AmbiguousLocalOrder 0 1)

  it "excludes joined neighbors from forces but refuses their overlapping reference" $ do
    let joined = Mesh [Sample (V2 x y) (V3 x y 0) | (x, y) <- [(0, 0), (1, 0), (1, 1), (0, 1)]] [(0, 1, 2), (0, 2, 3)]
    reference <- right (discoverLocalReference 1e-6 10 axis joined)
    localReferenceOrders reference `shouldBe` []
    Contact.localOverlapCandidates axis joined `shouldBe` Right []
    -- Pull the fourth corner inside the first triangle: these still share
    -- an edge, but now also occupy the same area. The diagnostic must see it.
    let overlapping = move (\i p -> if i == 3 then V3 0.8 0.2 0 else p) joined
    Contact.localOverlapCandidates axis overlapping `shouldBe` Right []
    case discoverLocalReference 0 10 axis overlapping of
      Left (UnsafeLocalReference report) -> contactPassed report `shouldBe` False
      other -> expectationFailure (show other)

  it "rejects a new overlap instead of inventing its order during correction" $ do
    let apart = pairMesh (triangleAt 0 0 ++ triangleAt 2 1)
        together = move (\i p -> if i >= 3 then p ^-^ V3 1.5 0 1 else p) apart
    reference <- right (discoverLocalReference 0 10 axis apart)
    localDiscoveredContacts reference apart `shouldBe` Right []
    localDiscoveredContacts reference together `shouldBe` Left (NewLocalContactPair 0 1)
    relaxLocalContact defaultSettings [] reference together `shouldBe` Left (LocalDiscoveryFailure (NewLocalContactPair 0 1))
    localReferenceOrders reference `shouldBe` []

  it "accepts a later overlap whose order follows through a third triangle" $ do
    let initial = Mesh (zipWith Sample (cycle [V2 0 0, V2 1 0, V2 0 1]) (triangleAt 0 0 ++ triangleAt 0.7 1 ++ triangleAt 1.4 2)) [(0, 1, 2), (3, 4, 5), (6, 7, 8)]
        together = move (\i p -> if i >= 6 then p ^-^ V3 1.3 0 0 else p) initial
    reference <- right (discoverLocalReference 0 10 axis initial)
    localReferenceOrders reference `shouldBe` [(0, 1), (1, 2)]
    rows <- right (localDiscoveredContacts reference together)
    rows `shouldSatisfy` (not . null)
    minimum (map contactGap rows) `shouldSatisfy` (> 0)

  it "uses geometry rather than triangle numbering or winding to pick the side" $ do
    let reordered = separated {triangles = [(5, 4, 3), (2, 1, 0)]}
    reference <- right (discoverLocalReference 0 10 axis reordered)
    localReferenceOrders reference `shouldBe` [(1, 0)]
    reversed <- right (discoverLocalReference 0 10 (V3 0 0 (-1)) separated)
    localReferenceOrders reversed `shouldBe` [(1, 0)]

  it "keeps candidates and gaps when the shape and direction rotate together" $ do
    let rotate (V3 x y z) = V3 z x y
        moved = move (\_ p -> rotate p ^+^ V3 3 (-2) 5) separated
    reference <- right (discoverLocalReference 0 10 axis separated)
    rotated <- right (discoverLocalReference 0 10 (rotate axis) moved)
    localReferenceOrders rotated `shouldBe` localReferenceOrders reference
    originalRows <- right (localDiscoveredContacts reference separated)
    rotatedRows <- right (localDiscoveredContacts rotated moved)
    let gaps = sort . map contactGap
    maximum (0 : zipWith (\a b -> abs (a - b)) (gaps originalRows) (gaps rotatedRows)) `shouldSatisfy` (< 1e-12)

  it "uses clipped triangle area, not bounding boxes or vertex inclusion alone" $ do
    let disjoint = pairMesh [V3 0 0 0, V3 2 0 0, V3 0 2 0, V3 2 2 1, V3 2 1.5 1, V3 1.5 2 1]
        edgesCross = pairMesh [V3 (-2) (-1) 0, V3 2 (-1) 0, V3 0 2 0, V3 (-2) 1 0.4, V3 2 1 0.4, V3 0 (-2) 0.4]
    localReferenceOrders <$> discoverLocalReference 0 10 axis disjoint `shouldBe` Right []
    localReferenceOrders <$> discoverLocalReference 0 10 axis edgesCross `shouldBe` Right [(0, 1)]

  it "handles an upright triangle but refuses pairs with no measurable height" $ do
    let upright = pairMesh [V3 (-2) (-2) 0, V3 2 (-2) 0, V3 0 3 0, V3 0 0 0.2, V3 0 0 0.6, V3 0 1 0.6]
        both = pairMesh [V3 0 0 0, V3 0 1 0, V3 0 0 1, V3 0 0 2, V3 0 1 2, V3 0 0 3]
    reference <- right (discoverLocalReference 0 10 axis upright)
    map Contact.localGapRange (localReferenceCandidates reference) `shouldBe` [Just (0.2, 0.6)]
    discoverLocalReference 0 10 axis both `shouldBe` Left (UncheckableLocalOrder 0 1)

  it "separates the reference search buffer from contact activation and preserves learned order" $ do
    let far = move (\i p -> if i >= 3 then p ^+^ V3 0 0 1 else p) separated
        near = move (\i p -> if i >= 3 then p ^-^ V3 0 0 0.19 else p) separated
        touching = move (\i p -> if i >= 3 then p ^-^ V3 0 0 0.2 else p) separated
        reversed = move (\i p -> if i >= 3 then p ^-^ V3 0 0 1 else p) separated
    empty <- right (discoverLocalReference 1e-6 0.03 axis far)
    localReferenceOrders empty `shouldBe` []
    localDiscoveredContacts empty near `shouldBe` Right []
    localDiscoveredContacts empty touching `shouldBe` Left (NewLocalContactPair 0 1)
    learned <- right (discoverLocalReference 1e-6 0.03 axis near)
    localDiscoveredContacts learned far `shouldSatisfy` (not . isLeft)
    rows <- right (localDiscoveredContacts learned reversed)
    minimum (map contactGap rows) `shouldSatisfy` (< (-0.7))
    forM_ [0, 1e-6, -1, 0 / 0, 1 / 0] $ \distance ->
      discoverLocalReference 1e-6 distance axis near `shouldBe` Left InvalidLocalSearchDistance

  it "requires clearance and refuses changed topology, material and invalid inputs" $ do
    case discoverLocalReference 0.3 10 axis separated of
      Left (LocalReferenceClearance gap) -> abs (gap + 0.1) `shouldSatisfy` (< 1e-12)
      other -> expectationFailure (show other)
    discoverLocalReference (-1) 10 axis separated `shouldBe` Left (LocalDiscoveryGeometry Contact.InvalidContactClearance)
    discoverLocalReference 0 10 (V3 0 0 0) separated `shouldBe` Left (LocalDiscoveryGeometry Contact.InvalidContactDirection)
    discoverLocalReference 0 10 axis (Mesh [] []) `shouldBe` Left (LocalDiscoveryGeometry Contact.EmptyContactMesh)
    reference <- right (discoverLocalReference 0 10 axis separated)
    let remapped = separated {samples = [s {sampleMaterial = V2 9 9} | s <- samples separated]}
    forM_ [remapped, separated {triangles = reverse (triangles separated)}] $ \mesh ->
      localDiscoveredContacts reference mesh `shouldBe` Left (LocalDiscoveryGeometry Contact.ChangedContactMaterial)

  it "does not attract a separated resting strip or accept an exhausted correction" $ do
    fixture <- right (curledPanel 8)
    let mesh = curlMesh fixture
        vertices = IM.fromList (zip [0 ..] (samples mesh))
    reference <- right (discoverLocalReference (curlClearance fixture) 10 axis mesh)
    quiet <- mapM (\hinge -> do (angle, _) <- right (hingeAngle hinge vertices); pure hinge {hingeRest = angle}) (curlHinges fixture)
    result <- right (relaxLocalContact defaultSettings quiet reference mesh)
    finalMesh result `shouldReturn` mesh
    converged result `shouldBe` True
    exhausted <- right (relaxLocalContact defaultSettings {iterationLimit = 0} (curlHinges fixture) reference mesh)
    converged exhausted `shouldBe` False

  it "grows the finer strip's history only at accepted separated encounters" $ do
    fixture <- right (curledPanelAt 16 22.25)
    let mesh = curlMesh fixture
        direction = V3 (-3) 0 1
        clearance = curlClearance fixture
    reference <- right (discoverLocalReference clearance 0.03 direction mesh)
    (result, learned) <- right (relaxLocalHistory defaultSettings (curlHinges fixture) reference mesh)
    converged result `shouldBe` True
    length (localReferenceOrders reference) `shouldBe` 4
    length (localReferenceOrders learned) `shouldBe` 10
    let events = localReferenceEncounters learned
    events `shouldSatisfy` (not . null)
    replayed <- foldM (\prior event -> right (extendLocalReference (encounterIteration event) prior (encounterMesh event))) reference events
    replayed `shouldBe` learned
    forM_ events $ \event -> do
      -- This regression learns at a saved accepted checkpoint. A trial that
      -- failed line search must not leave an observation at a different pose.
      checkpoints result `shouldSatisfy` any (\point -> completedIterations point == encounterIteration event && checkpointMesh point == encounterMesh event)
      forM_ (encounterCandidates event) $ \candidate -> case Contact.localGapRange candidate of
        Just (lo, hi) -> (lo > clearance + contactTolerance || hi < negate (clearance + contactTolerance)) `shouldBe` True
        Nothing -> expectationFailure "learned an unmeasurable encounter"
    forM_ (checkpoints result) $ \point -> do
      let current = checkpointMesh point
          previous = filter ((<= completedIterations point) . encounterIteration) events
      known <- foldM (\prior event -> right (extendLocalReference (encounterIteration event) prior (encounterMesh event))) reference previous
      localDiscoveredContacts known current `shouldSatisfy` (not . isLeft)
      localReferenceOrders reference `shouldSatisfy` all (`elem` localReferenceOrders known)
      triangles current `shouldBe` triangles mesh
      map sampleMaterial (samples current) `shouldBe` map sampleMaterial (samples mesh)
      componentCount current `shouldBe` 1
    final <- finalMesh result
    maxLengthError final `shouldSatisfy` (< 1e-7)
    report <- right (checkLocalTriangleContact direction (localReferenceOrders learned) final)
    checkedPanelPairs report `shouldBe` 496
    contactPassed report `shouldBe` True
    rows <- right (localDiscoveredContacts learned final)
    minimum (map contactGap rows) `shouldSatisfy` (>= negate contactTolerance)
    curlOwners fixture `shouldBe` replicate 32 (FaceId 0)

  it "keeps the eight-span result and records nothing for exhausted or stationary trials" $ do
    fixture <- right (curledPanelAt 8 44.5)
    let mesh = curlMesh fixture
        hinges = curlHinges fixture
    reference <- right (discoverLocalReference (curlClearance fixture) 0.03 (V3 (-3) 0 1) mesh)
    fixed <- right (relaxLocalContact defaultSettings hinges reference mesh)
    growing <- right (relaxLocalHistory defaultSettings hinges reference mesh)
    growing `shouldBe` (fixed, reference)
    (exhausted, unchanged) <- right (relaxLocalHistory defaultSettings {iterationLimit = 0} hinges reference mesh)
    converged exhausted `shouldBe` False
    unchanged `shouldBe` reference
    -- A proposed history must also be discarded when the current shape is
    -- already at rest: an equal-energy trial is not accepted.
    let shape = pairMesh (triangleAt 0 0 ++ triangleAt 0 1)
        far = shape {samples = [sample {sampleMaterial = let V3 x y _ = position sample in V2 x y} | sample <- samples shape]}
        near = move (\i p -> if i >= 3 then p ^-^ V3 0 0 0.99 else p) far
    empty <- right (discoverLocalReference 1e-6 0.03 axis far)
    (resting, retained) <- right (relaxLocalHistory defaultSettings [] empty near)
    converged resting `shouldBe` True
    retained `shouldBe` empty
    finalMesh resting `shouldReturn` near

  it "learns a new neighbor before contact and retains its side after separation" $ do
    let near = move (\i p -> if i >= 3 then p ^-^ V3 0 0 0.19 else p) separated
        reversed = move (\i p -> if i >= 3 then p ^-^ V3 0 0 1 else p) separated
    empty <- right (discoverLocalReference 1e-6 0.03 axis separated)
    learned <- right (extendLocalReference 1 empty near)
    localReferenceOrders learned `shouldBe` [(0, 1)]
    rows <- right (localDiscoveredContacts learned near)
    rows `shouldSatisfy` all ((> 0) . contactGap)
    extendLocalReference 2 learned separated `shouldBe` Right learned
    extendLocalReference 3 learned reversed `shouldBe` Right learned
    reversedRows <- right (localDiscoveredContacts learned reversed)
    minimum (map contactGap reversedRows) `shouldSatisfy` (< (-0.7))
    localReferenceOrders empty `shouldBe` []
    localReferenceEncounters empty `shouldBe` []

  it "refuses unknown touching, crossed and within-clearance encounters without learning" $ do
    empty <- right (discoverLocalReference 0.01 0.03 axis separated)
    let touching = move (\i (V3 x y z) -> V3 x y (if i >= 3 then 0 else z)) separated
        crossed = move (\i (V3 x y z) -> V3 x y (if i == 4 then -0.2 else z)) separated
        tooClose = move (\i (V3 x y z) -> V3 x y (if i >= 3 then 0.005 else z)) separated
    forM_ [touching, crossed, tooClose] $ \mesh -> do
      extendLocalReference 1 empty mesh `shouldBe` Left (NewLocalContactPair 0 1)
      relaxLocalHistory defaultSettings [] empty mesh `shouldBe` Left (LocalDiscoveryFailure (NewLocalContactPair 0 1))
    localReferenceEncounters empty `shouldBe` []
    let remapped = separated {samples = [s {sampleMaterial = V2 9 9} | s <- samples separated]}
    forM_ [remapped, separated {triangles = reverse (triangles separated)}] $ \mesh ->
      extendLocalReference 1 empty mesh `shouldBe` Left (LocalDiscoveryGeometry Contact.ChangedContactMaterial)

  it "uses the current flat patches when learning inside an initially flat sheet" $ do
    fixture <- right (curledPanelAt 8 44.5)
    let bent = curlMesh fixture
        flat = bent {samples = [sample {position = let V2 u v = sampleMaterial sample in V3 u v 0} | sample <- samples bent]}
        direction = V3 (-3) 0 1
    empty <- right (discoverLocalReference 1e-6 0.03 direction flat)
    learned <- right (extendLocalReference 1 empty bent)
    localReferenceOrders learned `shouldBe` [(0, 14), (0, 15), (1, 14), (1, 15)]
    localReferenceOrders empty `shouldBe` []

  it "checks new transitive orders outside the search radius and rejects cycles" $ do
    let initial = threeHeights [0, 0.2, 2]
    reference <- right (discoverLocalReference 1e-6 0.3 axis initial)
    localReferenceOrders reference `shouldBe` [(0, 1)]
    learned <- right (extendLocalReference 1 reference (threeHeights [0, 0.2, 0.4]))
    localReferenceOrders learned `shouldBe` [(0, 1), (1, 2)]
    -- B remains above A in history even while its numerical correction puts
    -- B below A. Learning B < C would imply the wrong A < C outside the buffer.
    case extendLocalReference 1 reference (threeHeights [0, -1, -0.8]) of
      Left (LocalReferenceClearance gap) -> gap `shouldSatisfy` (< (-0.7))
      other -> expectationFailure (show other)
    wider <- right (discoverLocalReference 1e-6 0.6 axis initial)
    extendLocalReference 1 wider (threeHeights [0, -1, -0.5]) `shouldBe` Left (LocalDiscoveryGeometry Contact.CyclicContactOrder)

threeHeights :: [Double] -> MaterialMesh
threeHeights heights = Mesh (zipWith Sample (cycle [V2 0 0, V2 1 0, V2 0 1]) (concatMap (triangleAt 0) heights)) [(0, 1, 2), (3, 4, 5), (6, 7, 8)]

axis :: V3
axis = V3 0 0 1

separated :: MaterialMesh
separated = pairMesh [V3 (-2) (-2) 0, V3 2 (-2) 0, V3 0 3 0, V3 (-0.3) 0 0.2, V3 0.3 0 0.2, V3 0 0.6 0.2]

triangleAt :: Double -> Double -> [V3]
triangleAt x z = [V3 x 0 z, V3 (x + 1.2) 0 z, V3 x 1 z]

pairMesh :: [V3] -> MaterialMesh
pairMesh points = Mesh (zipWith Sample [V2 0 0, V2 1 0, V2 0 1, V2 2 0, V2 3 0, V2 2 1] points) [(0, 1, 2), (3, 4, 5)]

move :: (Int -> V3 -> V3) -> MaterialMesh -> MaterialMesh
move f mesh = mesh {samples = [s {position = f i (position s)} | (i, s) <- zip [0 ..] (samples mesh)]}

finalMesh :: Relaxation -> IO MaterialMesh
finalMesh result = case reverse (checkpoints result) of point : _ -> pure (checkpointMesh point); [] -> fail "no final checkpoint"

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
