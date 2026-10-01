-- | Whole-sheet attachment and drawing controls, without a material solve.
module WholeCraneSpec (spec) where

import BodyPatch
import Control.Monad (forM, forM_, when)
import CranePocket
import CraneSpread
import Data.Aeson (Value (..))
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.List (find)
import Data.Set qualified as S
import Data.Text qualified as T
import FoldMaterial (componentCount, meshEdges)
import IllustrationComparison (illustrationScale)
import PaperScreen (FloorPair (..), Turning (..), pictureFloor, sheetChords)
import ScreenReport
import Senbazuru.Explain (explain)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface
import Senbazuru.Render.Camera (basisFrom)
import Senbazuru.Render.Fidelity (Geometry (..))
import Test.Glb (Glb (..), at, items, parseGlb)
import Test.Hspec
import WholeCrane
import WholeCraneExport
import WholeCraneScreen

spec :: Spec
spec = beforeAll load $ describe "one connected whole-crane candidate" $ do
  it "keeps the complete material disk and all original vertices" $ \(_, _, study) -> do
    let fixture = wholeSpread study
        mesh = spreadMesh fixture
        original = refinedMesh (spreadRefined fixture)
    componentCount mesh `shouldBe` 1
    length (samples mesh) `shouldBe` 237
    length (triangles mesh) `shouldBe` 448
    length (samples mesh) - length (meshEdges mesh) + length (triangles mesh) `shouldBe` 1
    triangles mesh `shouldBe` triangles original
    map sampleMaterial (samples mesh) `shouldBe` map sampleMaterial (samples original)
    wholeMappedVertices study `shouldBe` 87
    -- Four originally coincident material points must stay distinct ids.
    let lips = pocketLips (wholeMap study)
    length lips `shouldBe` 4
    S.size (S.fromList lips) `shouldBe` 4

  it "copies the body core exactly and keeps neck and tail unheld" $ \(_, patch, study) -> do
    let mesh = spreadMesh (wholeSpread study)
        body = samples (spreadMesh (patchSpread patch))
        held = spreadPins (wholeSpread study)
    spreadHeldError (wholeSpread study) mesh `shouldBe` 0
    mapM_
      ( \(i, p) ->
          when (S.member i (wholeCore study)) $ [norm (position p ^-^ position q) | q <- body, norm (sampleMaterial p ^-^ sampleMaterial q) < 1e-12] `shouldSatisfy` (\ds -> not (null ds) && all (< 1e-12) ds)
      )
      (zip [0 ..] (samples mesh))
    [IM.member i held | (name, i) <- wholeMarks study, name `elem` ["neck-head", "tail"]] `shouldBe` [False, False]

  it "spreads both tips to opposite sides and reports a fuller body" $ \(_, _, study) -> do
    let mesh = spreadMesh (wholeSpread study)
        points = IM.fromList (zip [0 ..] (map position (samples mesh)))
        tip name = lookup name (wholeMarks study) >>= (`IM.lookup` points)
    case (tip "wing-a", tip "wing-b") of
      (Just a, Just b) -> do
        v3z a `shouldSatisfy` (> 0.1)
        v3z b `shouldSatisfy` (< -0.1)
      _ -> expectationFailure "missing wing tips"
    values <- right (wholeMeasurements study mesh)
    lookup "bodyDepth" values `shouldSatisfy` maybe False (> 0.05)
    lookup "wingTipSeparation" values `shouldSatisfy` maybe False (> 0.3)

  it "refuses changed material and a different patch target" $ \(atlas, patch, _) -> do
    let saved = spreadMesh (patchSpread patch)
    wholeCrane atlas patch {patchDegrees = 5} saved `shouldSatisfy` isLeft
    wholeCrane atlas patch saved {samples = [p {sampleMaterial = sampleMaterial p ^+^ V2 0.01 0} | p <- samples saved]} `shouldSatisfy` isLeft
    wholeCrane atlas patch saved {triangles = drop 1 (triangles saved)} `shouldSatisfy` isLeft

  it "changes wing spread while preserving the cushion, material and arch lengths" $ \(_, _, study) -> do
    middle <- right (narrowPillowCrane study)
    poses <- traverse (\amount -> right (pillowCraneAtSpread amount study)) [0, 0.25, 0.5, 0.75, 1]
    midpoint <- right (pillowCraneAtSpread 0.5 study)
    map position (samples midpoint) `shouldBe` map position (samples middle)
    let base = refinedMesh (spreadRefined (wholeSpread study))
        core mesh = [position p | (i, p) <- zip [0 ..] (samples mesh), S.member i (wholeCore study)]
        -- Exclusive outer-wing triangles keep their shape when the arch
        -- turns. The body-to-wing collar is deliberately free to distort.
        outerEdges = [(a, b) | (a, b) <- meshEdges base, Just p <- [IM.lookup a originals], v3y (position p) < 0.25, Just q <- [IM.lookup b originals], v3y (position q) < 0.25]
        originals = IM.fromList (zip [0 ..] (samples base))
        lengths mesh = let points = IM.fromList (zip [0 ..] (map position (samples mesh))) in [norm (p ^-^ q) | (a, b) <- outerEdges, Just p <- [IM.lookup a points], Just q <- [IM.lookup b points]]
    outerEdges `shouldSatisfy` (not . null)
    forM_ poses $ \mesh -> do
      core mesh `shouldBe` core middle
      triangles mesh `shouldBe` triangles base
      map sampleMaterial (samples mesh) `shouldBe` map sampleMaterial (samples base)
      zipWith (\a b -> abs (a - b)) (lengths mesh) (lengths middle) `shouldSatisfy` all (< 1e-12)
    measurements <- traverse (right . wholeMeasurements study) poses
    let spans = [spanValue | values <- measurements, Just spanValue <- [lookup "wingTipSeparation" values]]
    length spans `shouldBe` 5
    and (zipWith (<) spans (drop 1 spans)) `shouldBe` True

  it "refuses a non-finite or out-of-range wing spread" $ \(_, _, study) ->
    forM_ [-0.1, 1.1, 0 / 0, 1 / 0, -(1 / 0)] $ \amount ->
      pillowCraneAtSpread amount study `shouldSatisfy` isLeft

  forM_ [("a wide pillow", pillowCrane), ("a less spread pillow", compactPillowCrane), ("a narrower pillow", narrowPillowCrane)] $ \(description, makePillow) ->
    it ("opens " ++ description ++ " on the same sheet with separate wings and intact tips") $ \(_, _, study) -> do
      mesh <- right (makePillow study)
      let base = refinedMesh (spreadRefined (wholeSpread study))
          points = IM.fromList (zip [0 ..] (map position (samples mesh)))
          tip name = lookup name (wholeMarks study) >>= (`IM.lookup` points)
      triangles mesh `shouldBe` triangles base
      map sampleMaterial (samples mesh) `shouldBe` map sampleMaterial (samples base)
      componentCount mesh `shouldBe` 1
      length (samples mesh) - length (meshEdges mesh) + length (triangles mesh) `shouldBe` 1
      all (\p -> all (\v -> not (isNaN v || isInfinite v)) [v3x p, v3y p, v3z p]) (IM.elems points) `shouldBe` True
      case (tip "wing-a", tip "wing-b", tip "neck-head", tip "tail") of
        (Just a, Just b, Just neck, Just tailTip) -> do
          v3z a * v3z b `shouldSatisfy` (< 0)
          norm (a ^-^ b) `shouldSatisfy` (> 0.5)
          v3x neck `shouldSatisfy` (< 1)
          v3x tailTip `shouldSatisfy` (> 1)
        _ -> expectationFailure "missing pillow landmarks"
      -- Negative Y is up: a cushion's centre stands above its rim, while its
      -- width spans both sides of the old flat packet's Z=0 plane.
      case tip "centre" of
        Just centre -> v3y centre `shouldSatisfy` (< 0.44)
        _ -> expectationFailure "missing pillow centre"
      values <- right (wholeMeasurements study mesh)
      lookup "bodyDepth" values `shouldSatisfy` maybe False (> 0.2)

  -- The complete scene alone leaves a viewer to pick between coincident
  -- layers by its depth buffer (PRD 11, R-11-10). Exporting it alone, or
  -- leading with it, turns this red.
  it "gives the viewers visible paper first and every layer second" $ \(_, _, study) -> do
    let fixture = wholeSpread study
    closed <- right (cranePose study "before")
    sheet <- right (spreadSurface fixture (craneMesh closed))
    glb <- right (viewerGlb closed sheet) >>= parseGlb
    map (at "name") (items (at "scenes" (glbJson glb))) `shouldBe` [String "Visible paper", String "Complete paper"]
    at "scene" (glbJson glb) `shouldBe` Number 0
    -- A folded pose keeps its plain name, and its file says it was folded.
    map (at "name") (items (at "nodes" (glbJson glb))) `shouldBe` replicate 2 (String "Closed crane")
    recordedGeometry glb `shouldBe` String "rigid panels"

  -- PRD 11's R-11-2: a pose placed rather than folded says so in its file.
  -- Calling a placed pose folded, or writing the same level or name whatever
  -- the pose, turns this or the test above red.
  it "records More tucked as a shape sketch in its GLB, and only the closed crane as folded" $ \(_, _, study) -> do
    poses <- right (wholeCranePoses study)
    [(craneStem p, craneGeometry p) | p <- poses, craneGeometry p /= AsPrescribed] `shouldBe` [("before", RigidPanels)]
    [craneCaveat p | p <- poses, craneStem p == "before"] `shouldBe` [Nothing]
    tucked <- maybe (fail "no spread-0 pose") pure (find ((== "spread-0") . craneStem) poses)
    sheet <- right (spreadSurface (wholeSpread study) (craneMesh tucked))
    glb <- right (viewerGlb tucked sheet) >>= parseGlb
    recordedGeometry glb `shouldBe` String "as prescribed"
    map (at "name") (items (at "nodes" (glbJson glb))) `shouldBe` replicate 2 (String "More tucked · visual target · shape sketch")

  -- PRD 11's A-11-1, with the false-crease and core figures of its research
  -- (H1, Y3, Y4) on the same construction. Computed along edges only, the 3D
  -- floor would be 17.71 px, set by the edge 46-213.
  it "screens More tucked as a shape paper cannot take" $ \(_, _, study) -> do
    tucked <- right (cranePose study "spread-0")
    screen <- right (screenPose study tucked)
    let mesh = craneMesh tucked
    fmap floorVertices (screenFloor screen) `shouldBe` Just (37, 46)
    fmap (floorPixels crane) (screenFloor screen) `shouldSatisfy` maybe False (near 20.04 0.01)
    -- In the picture, pairs 46-182 and 46-230 tie to within rounding; either
    -- sets the same floor.
    upright <- uprightFloor mesh
    fmap floorVertices upright `shouldSatisfy` (`elem` [Just (46, 182), Just (46, 230)])
    fmap (floorPixels crane) upright `shouldSatisfy` maybe False (near 17.14 0.01)
    screenCrossings screen `shouldBe` 345
    fmap snd (screenDeepestReach screen) `shouldBe` Just (2, 29)
    fmap ((pixelsPerSheet crane *) . fst) (screenDeepestReach screen) `shouldSatisfy` maybe False (near 17.35 0.01)
    screenStretch screen `shouldSatisfy` near 1.068 0.001
    screenSquash screen `shouldSatisfy` near 0.836 0.001
    turningJoins (screenTurning screen) `shouldBe` 15
    turningTotal (screenTurning screen) `shouldSatisfy` near 144.8 0.1
    fmap turningJoins (screenTurningFiner screen) `shouldBe` Just 26
    fmap turningTotal (screenTurningFiner screen) `shouldSatisfy` maybe False (near 142.18 0.01)
    screenCoreLength screen `shouldSatisfy` maybe False (near 0.414 0.001)
    fst (screenCentreFolds screen) `shouldSatisfy` maybe False (near 14.04 0.05)
    snd (screenCentreFolds screen) `shouldSatisfy` maybe False (near 4.03 0.05)
    verdictOverall (screenVerdict crane screen) `shouldBe` Fails

  -- PRD 11's A-11-2, the fold half: More tucked made again with every
  -- triangle split into four, and again, keeps its false-crease turning
  -- within 5%, as a fold would; research note Y3 measured 145, 142 and 141.
  -- It is not a fold. Two levels finer still, at 28,672 and 114,688
  -- triangles and too slow to run here, the turning falls to 96 and 20
  -- (docs/notes/fold-or-curve.md). So this holds the measure to A-11-2's
  -- figures; it does not show that More tucked is folded. Counting joins
  -- instead, 15, 26 and 56, turns it red.
  it "keeps More tucked's false-crease turning within 5% at 448, 1,792 and 7,168 triangles" $ \(_, _, study) -> do
    tucked <- right (cranePose study "spread-0")
    turnings <- forM [1, 2, 3] $ \levels -> do
      refined <- right (refinedCrane levels (wholeMap study))
      right (turningOn refined study (craneConstruction tucked)) >>= maybe (fail "More tucked was not made again") pure
    map turningJoins turnings `shouldBe` [15, 26, 56]
    let totals = map turningTotal turnings
    (maximum totals - minimum totals) / maximum totals `shouldSatisfy` (< 0.05)

  -- The first candidate is placed around the saved body and not made again
  -- on a finer mesh, so its screen has no finer figure. Its own mesh already
  -- bends four joins past 45 degrees, so its false creases fail whatever the
  -- finer level would say; reading an unmeasured level as enough to save it
  -- turns this red.
  it "does not make the first candidate again one level finer" $ \(_, _, study) -> do
    candidate <- right (cranePose study "after")
    screen <- right (screenPose study candidate)
    screenTurningFiner screen `shouldBe` Nothing
    turningJoins (screenTurning screen) `shouldBe` 4
    verdictFalseCreases (screenVerdict crane screen) `shouldBe` Fails

  -- An error while making a pose again names the refinement it came from,
  -- since its vertex numbers are in no file the gallery writes. The finer
  -- mesh's hinges reach past the study's own vertices; reporting that as an
  -- error of the pose itself turns this red.
  it "says which refinement an error in a remade pose came from" $ \(_, _, study) -> do
    tucked <- right (cranePose study "spread-0")
    (coarse, _) <- right (refinedCrane 1 (wholeMap study))
    (_, finerHinges) <- right (finerCrane study)
    case turningOn (coarse, finerHinges) study (craneConstruction tucked) of
      Left err -> explain err `shouldSatisfy` T.isPrefixOf "on the pose made again on 448 triangles: "
      Right _ -> expectationFailure "the finer mesh's hinges measured the study's own mesh"

  it "screens the closed crane as paper and measures the first candidate's picture floor (A-11-1)" $ \(_, _, study) -> do
    let fixture = wholeSpread study
    folded <- right (cranePose study "before")
    closed <- right (screenPose study folded)
    screenVerdict crane closed `shouldBe` Verdict True True True Passes
    screenTurningFiner closed `shouldBe` Just (Turning 0 0)
    fmap (floorPixels crane) (screenFloorAtScreen closed) `shouldBe` Just 0
    screenCrossings closed `shouldBe` 0
    screenCoreLength closed `shouldSatisfy` maybe False (near 0.235 0.001)
    fst (screenCentreFolds closed) `shouldSatisfy` maybe False (near 180 0.5)
    snd (screenCentreFolds closed) `shouldSatisfy` maybe False (near 180 0.5)
    upright <- uprightFloor (spreadMesh fixture)
    fmap (floorPixels crane) upright `shouldSatisfy` maybe False (near 1.02 0.01)

-- | The whole crane's page, which draws every pose at 600 px to a sheet
-- unit: the scale PRD 11's figures for More tucked are in.
crane :: PageScale
crane = PageScale illustrationScale

-- | The geometry level a GLB's fidelity record gives, or null.
recordedGeometry :: Glb -> Value
recordedGeometry glb = at "geometry" (at "fidelity" (at "senbazuru" (at "extras" (glbJson glb))))

-- | The no-stretch floor in the gallery's upright picture; a sheet the screen
-- refuses fails the test with the reason.
uprightFloor :: MaterialMesh -> IO (Maybe FloorPair)
uprightFloor mesh = do
  basis <- maybe (fail "the upright camera has no basis") pure (basisFrom (V3 1 (sqrt 2) (-1)) (V3 0 (-1) 0))
  chords <- right (sheetChords mesh)
  pure (pictureFloor chords basis 0 mesh)

near :: Double -> Double -> Double -> Bool
near expected tolerance actual = abs (actual - expected) <= tolerance

load :: IO (PocketMap, BodyPatch, WholeCrane)
load = do
  source <- keyFrame <$> (loadFoldFile "examples/crane.fold" >>= right)
  atlas <- right (buildCranePocket source)
  patch <- right (bodyPatch atlas 1 10)
  archived <- keyFrame <$> (loadFoldFile "study/fold-material/fixtures/whole-crane-body.fold" >>= right)
  sheet <- right (surfaceFromFrame archived >>= requireMaterialCoordinates)
  let mesh = (spreadMesh (patchSpread patch)) {samples = surfaceSamples sheet}
      savedPatch = patch {patchSpread = (patchSpread patch) {spreadMesh = mesh}}
  _ <- right (spreadSurface (patchSpread patch) mesh)
  study <- right (wholeCrane atlas savedPatch mesh)
  pure (atlas, savedPatch, study)

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
