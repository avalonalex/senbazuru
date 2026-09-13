module CorrectionSweepSpec (spec) where

import Control.Monad (forM_, when)
import CorrectionExample
import CorrectionSweep
import Data.Either (isLeft)
import Data.List (foldl')
import FoldMaterial (componentCount)
import FoldRelaxation
import LocalContactDiscovery
import PanelContact (checkLocalTriangleContact, contactPassed)
import SelfContactExample
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Test.Hspec
import Test.Hspec.QuickCheck (prop)
import Test.QuickCheck (choose, forAll)

spec :: Spec
spec = describe "numerical correction sweep" $ do
  it "catches the shortcut through a connected square with length-preserving endpoints" $ do
    let (initial, finish) = crossingCorrection
    forM_ [initial, finish] $ \mesh -> do
      componentCount mesh `shouldBe` 1
      maxLengthError mesh `shouldSatisfy` (< 1e-14)
      right (checkLocalTriangleContact (V3 0 0 1) [] mesh) >>= (`shouldSatisfy` contactPassed)
    sweep <- right (prepareCorrection initial finish)
    result <- right (checkCorrection defaultCorrectionSettings sweep)
    correctionOutcome result `shouldBe` CorrectionCollision 0.5 [(0, 1)]
    witness <- right (correctionMeshAt sweep 0.5)
    componentCount witness `shouldBe` 1
    map sampleMaterial (samples witness) `shouldBe` map sampleMaterial (samples initial)

  it "refuses an interior crossing despite two separated endpoints" $ do
    let finish = shiftSecond (V3 0 0 (-3)) start
    forM_ [start, finish] $ \mesh -> right (checkLocalTriangleContact (V3 0 0 1) [] mesh) >>= (`shouldSatisfy` contactPassed)
    sweep <- right (prepareCorrection start finish)
    result <- right (checkCorrection defaultCorrectionSettings sweep)
    case correctionOutcome result of
      CorrectionCollision t pairs -> do
        t `shouldSatisfy` (\x -> x > 0 && x < 1)
        pairs `shouldBe` [(0, 1)]
        witness <- right (correctionMeshAt sweep t)
        report <- right (checkLocalTriangleContact (V3 0 0 1) [] witness)
        contactPassed report `shouldBe` False
      other -> expectationFailure (show other)

  it "clears separation throughout a changing shape and preserves endpoint identities" $ do
    let finish = shiftSecond (V3 0.3 0.1 1) start
    sweep <- right (prepareCorrection start finish)
    correctionOutcome <$> checkCorrection defaultCorrectionSettings sweep `shouldBe` Right CorrectionClear
    correctionMeshAt sweep 0 `shouldBe` Right start
    correctionMeshAt sweep 1 `shouldBe` Right finish
    forM_ [0, 0.25, 0.5, 0.75, 1] $ \t -> do
      mesh <- right (correctionMeshAt sweep t)
      triangles mesh `shouldBe` triangles start
      map sampleMaterial (samples mesh) `shouldBe` map sampleMaterial (samples start)

  it "keeps a shared edge lawful while its neighboring triangle bends" $ do
    let initial = meshFrom [V3 0 0 0, V3 1 0 0, V3 0 1 0, V3 1 1 0] [(0, 1, 2), (1, 3, 2)]
        finish = move (\i p -> if i == 3 then p ^+^ V3 0 0 0.4 else p) initial
    sweep <- right (prepareCorrection initial finish)
    correctionOutcome <$> checkCorrection defaultCorrectionSettings sweep `shouldBe` Right CorrectionClear

  it "does not exempt a shared-corner triangle crossing its neighbor" $ do
    let initial = meshFrom [V3 0 0 0, V3 1 0 0, V3 0 1 0, V3 0.2 0.2 1, V3 0.4 0.2 1] [(0, 1, 2), (0, 3, 4)]
        finish = move (\i (V3 x y z) -> V3 x y (if i >= 3 then -z else z)) initial
    sweep <- right (prepareCorrection initial finish)
    result <- right (checkCorrection defaultCorrectionSettings sweep)
    correctionOutcome result `shouldSatisfy` (/= CorrectionClear)

  it "refuses a triangle collapse even without another triangle" $ do
    let initial = meshFrom [V3 0 0 0, V3 1 0 0, V3 0 1 0] [(0, 1, 2)]
        finish = move (\i (V3 x y z) -> if i == 2 then V3 x (-y) z else V3 x y z) initial
    sweep <- right (prepareCorrection initial finish)
    correctionOutcome <$> checkCorrection defaultCorrectionSettings sweep `shouldBe` Right (CorrectionDegenerate 0.5 [0])

  it "never treats exhausted separation bounds as clear" $ do
    sweep <- right (prepareCorrection start (shiftSecond (V3 0 0 (-3)) start))
    result <- right (checkCorrection (CorrectionSettings 0 1) sweep)
    case correctionOutcome result of
      CorrectionUnresolved {} -> pure ()
      other -> expectationFailure (show other)
    correctionIntervals result `shouldBe` 1

  it "clears a joined corner without treating its neighbors as disjoint" $ do
    let initial = meshFrom [V3 0 0 0, V3 1 0 0, V3 0 1 0, V3 (-1) 0 0, V3 0 (-1) 0] [(0, 1, 2), (0, 3, 4)]
        finish = move (\i p -> if i >= 3 then p ^+^ V3 0 0 0.2 else p) initial
    sweep <- right (prepareCorrection initial finish)
    correctionOutcome <$> checkCorrection defaultCorrectionSettings sweep `shouldBe` Right CorrectionClear

  it "blocks a nondyadic collapse by unresolved bounds when no sample hits it" $ do
    let initial = meshFrom [V3 0 0 0, V3 1 0 0, V3 0 1 0] [(0, 1, 2)]
        finish = move (\i (V3 x y z) -> V3 x (if i == 2 then -2 else y) z) initial
    sweep <- right (prepareCorrection initial finish)
    result <- right (checkCorrection (CorrectionSettings 8 64) sweep)
    case correctionOutcome result of
      CorrectionUnresolved lo hi _ faces -> do
        lo `shouldSatisfy` (< (1 / 3))
        hi `shouldSatisfy` (> (1 / 3))
        faces `shouldBe` [0]
      other -> expectationFailure (show other)

  it "keeps the outcome under coordinate permutation, translation and reversed travel" $ do
    let (initial, finish) = crossingCorrection
        transform (V3 x y z) = V3 (z + 3) (x - 2) (y + 5)
    forM_ [(initial, finish), (finish, initial), (move (const transform) initial, move (const transform) finish)] $ \(a, b) -> do
      sweep <- right (prepareCorrection a b)
      correctionOutcome <$> checkCorrection defaultCorrectionSettings sweep `shouldBe` Right (CorrectionCollision 0.5 [(0, 1)])

  prop "clears positive affine separation over the whole path" $
    forAll (choose (0.01, 3)) $ \height -> forAll (choose (0.01, 3)) $ \finishHeight ->
      let initial = move (\i (V3 x y z) -> V3 x y (if i >= 3 then z + height else z)) start
          finish = shiftSecond (V3 0.7 (-0.2) (finishHeight - height)) initial
       in (prepareCorrection initial finish >>= checkCorrection defaultCorrectionSettings) `shouldSatisfy` (\case Right report -> correctionOutcome report == CorrectionClear; Left _ -> False)

  it "settles a safe opening with every accepted correction checked" $ do
    fixture <- right openingStrip
    reference <- right (discoverLocalReference (curlClearance fixture) 0.03 (V3 (-3) 0 1) (curlMesh fixture))
    result <- right (relaxSweptLocalHistory defaultSettings defaultCorrectionSettings (curlHinges fixture) reference (curlMesh fixture))
    converged (sweptRelaxation result) `shouldBe` True
    verifyAccepted fixture result
    final <- lastMesh (sweptRelaxation result)
    maxLengthError final `shouldSatisfy` (< 1e-7)
    localReferenceOrders (sweptReference result) `shouldBe` localReferenceOrders reference
    exhausted <- right (relaxSweptLocalHistory defaultSettings {iterationLimit = 0} defaultCorrectionSettings (curlHinges fixture) reference (curlMesh fixture))
    converged (sweptRelaxation exhausted) `shouldBe` False
    sweptSteps exhausted `shouldBe` []
    sweptReference exhausted `shouldBe` reference

  it "checks every closing correction and requires valid lengths when it settles" $ do
    fixture <- right (curledPanelAt 16 22.25)
    reference <- right (discoverLocalReference (curlClearance fixture) 0.03 (V3 (-3) 0 1) (curlMesh fixture))
    result <- right (relaxSweptLocalHistory defaultSettings defaultCorrectionSettings (curlHinges fixture) reference (curlMesh fixture))
    verifyAccepted fixture result
    final <- lastMesh (sweptRelaxation result)
    -- Near contact, platform rounding can change which trial the nonlinear
    -- line search accepts. A stalled run and a settled run must BOTH keep the
    -- same motion/contact guarantees; a particular outcome is not the rule.
    when (converged (sweptRelaxation result)) $
      maxLengthError final `shouldSatisfy` (<= lengthTolerance defaultSettings)
    right (checkLocalTriangleContact (V3 (-3) 0 1) (localReferenceOrders (sweptReference result)) final) >>= (`shouldSatisfy` contactPassed)
    forM_ (localReferenceEncounters (sweptReference result)) $ \event ->
      sweptSteps result `shouldSatisfy` any (\step -> correctionIteration step == encounterIteration event && correctionFinish step == encounterMesh event)

  it "refuses invalid settings, progress and changed material or topology" $ do
    sweep <- right (prepareCorrection start start)
    forM_ [CorrectionSettings (-1) 1, CorrectionSettings 31 1, CorrectionSettings 1 0] $ \settings ->
      checkCorrection settings sweep `shouldBe` Left InvalidCorrectionSettings
    forM_ [-0.1, 1.1, 0 / 0, 1 / 0] $ \t -> correctionMeshAt sweep t `shouldBe` Left InvalidCorrectionProgress
    prepareCorrection start start {triangles = reverse (triangles start)} `shouldBe` Left ChangedCorrectionMaterial
    let changed = start {samples = [s {sampleMaterial = V2 99 99} | s <- samples start]}
    prepareCorrection start changed `shouldBe` Left ChangedCorrectionMaterial
    prepareCorrection (Mesh [] []) (Mesh [] []) `shouldBe` Left EmptyCorrectionMesh
    let invalid = move (\_ _ -> V3 (0 / 0) 0 0) start
    prepareCorrection start invalid `shouldSatisfy` isLeft
    let missing = start {triangles = [(0, 1, 99)]}
    prepareCorrection missing missing `shouldBe` Left (MissingCorrectionVertex 99)
    let collapsed = move (\_ _ -> V3 0 0 0) start
    prepareCorrection start collapsed `shouldBe` Left (InvalidCorrectionTriangle 0)

verifyAccepted :: CurledPanel -> SweptRelaxation -> IO ()
verifyAccepted fixture result = do
  let steps = sweptSteps result
      initial = curlMesh fixture
  steps `shouldSatisfy` (not . null)
  forM_ (zip (initial : map correctionFinish steps) steps) $ \(previous, step) -> do
    correctionStart step `shouldBe` previous
    let current = correctionFinish step
    triangles current `shouldBe` triangles initial
    map sampleMaterial (samples current) `shouldBe` map sampleMaterial (samples initial)
    componentCount current `shouldBe` 1
    replay <- right (prepareCorrection previous current >>= checkCorrection defaultCorrectionSettings)
    replay `shouldBe` correctionCheck step
    correctionOutcome replay `shouldBe` CorrectionClear
  lastMesh (sweptRelaxation result) `shouldReturn` foldl' (\_ step -> correctionFinish step) initial steps

lastMesh :: Relaxation -> IO MaterialMesh
lastMesh result = case reverse (checkpoints result) of
  point : _ -> pure (checkpointMesh point)
  [] -> fail "missing final checkpoint"

start :: MaterialMesh
start = meshFrom [V3 (-1) (-1) 0, V3 1 (-1) 0, V3 0 1 0, V3 0 (-0.3) 1, V3 0 0.3 1, V3 0 0 1.5] [(0, 1, 2), (3, 4, 5)]

meshFrom :: [V3] -> [Triangle] -> MaterialMesh
meshFrom points = Mesh (zipWith (\i p -> Sample (V2 i (i * i)) p) [0 ..] points)

shiftSecond :: V3 -> MaterialMesh -> MaterialMesh
shiftSecond delta = move (\i p -> if i >= 3 then p ^+^ delta else p)

move :: (Int -> V3 -> V3) -> MaterialMesh -> MaterialMesh
move f mesh = mesh {samples = [s {position = f i (position s)} | (i, s) <- zip [0 ..] (samples mesh)]}

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
