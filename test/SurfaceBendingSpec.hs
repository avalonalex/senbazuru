-- | The adapter must follow material topology, not recognize a particular
-- drawing. Known rigid equilibria independently test its signed controls.
module SurfaceBendingSpec (spec) where

import Control.Monad (forM_)
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.List (sort)
import Data.Map.Strict qualified as M
import FoldBending
import FoldMaterial (areaRatio, componentCount)
import FoldRelaxation
import PanelContact
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types (Assignment (..), EdgeId (..), FaceId (..), FoldFile (..), Frame (..), VertexId (..), emptyFrame)
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Folding (foldFrameWith)
import Senbazuru.Origami.Surface
import StudyCase
import Test.Hspec

spec :: Spec
spec = describe "bending from shared crease identities" $ do
  it "keeps a diagonal crease's source id, signed target and total stiffness through refinement" $ do
    sheet <- starting diagonal [0, 0, 0, 0, 60]
    forM_ [0 .. 3] $ \level -> do
      (refined, hinges) <- right (buildSurfaceHinges defaultBending level sheet (M.singleton (EdgeId 4) (2 * pi / 3)))
      let creases = [h | h <- hinges, hingeRole h == SurfaceCrease (EdgeId 4)]
      length creases `shouldBe` 2 ^ level
      map hingeRest creases `shouldBe` replicate (2 ^ level) (2 * pi / 3)
      abs (sum (map hingeStiffness creases) - sqrt 2) `shouldSatisfy` (< 1e-12)
      forM_ creases $ \h -> do
        angle <- angleOf (refinedMesh refined) h
        abs (angle - pi / 3) `shouldSatisfy` (< 1e-12)
      forM_ [h | h <- hinges, hingeRole h == PanelBend] $ \h -> hingeRest h `shouldBe` 0
  it "does not use the current pose as an implicit rest-angle control" $ do
    sheet <- starting diagonal [0, 0, 0, 0, 60]
    buildSurfaceHinges defaultBending 1 sheet M.empty `shouldBe` Left (MissingRestAngle (EdgeId 4))
  it "is independent of material origin, in-plane orientation and spatial placement" $ do
    let moved = diagonal {verticesCoords = [[3 - y, 2 + x] | [x, y] <- verticesCoords diagonal]}
    a <- starting diagonal [0, 0, 0, 0, 60]
    b <- starting moved [0, 0, 0, 0, 60]
    (ra, ha) <- right (buildSurfaceHinges defaultBending 2 a target)
    (rb, hb) <- right (buildSurfaceHinges defaultBending 2 b target)
    ha `shouldBe` hb
    refinedEdges ra `shouldBe` refinedEdges rb
    ea <- right (bendingEnergy ha (refinedMesh ra))
    eb <- right (bendingEnergy hb (refinedMesh rb))
    abs (fst ea - fst eb) `shouldSatisfy` (< 1e-12)
    abs (snd ea - snd eb) `shouldSatisfy` (< 1e-12)
  it "follows edge renumbering and direction rather than a fixture's crease index" $ do
    let renumbered = diagonal {edgesVertices = reverse [(b, a) | (a, b) <- edgesVertices diagonal], edgesAssignment = reverse (edgesAssignment diagonal)}
    sheet <- starting renumbered [60, 0, 0, 0, 0]
    (refined, hinges) <- right (buildSurfaceHinges defaultBending 1 sheet (M.singleton (EdgeId 0) (2 * pi / 3)))
    let creases = [h | h <- hinges, hingeRole h /= PanelBend]
    map hingeRole creases `shouldBe` replicate 2 (SurfaceCrease (EdgeId 0))
    forM_ creases $ \h -> do
      angle <- angleOf (refinedMesh refined) h
      abs (angle - pi / 3) `shouldSatisfy` (< 1e-12)
  it "keeps mountain signs and requires an explicit sign for unassigned creases" $ do
    forM_ [Mountain, Unassigned] $ \assignment -> do
      sheet <- starting diagonal {edgesAssignment = replicate 4 Border ++ [assignment]} [0, 0, 0, 0, -60]
      (refined, hinges) <- right (buildSurfaceHinges defaultBending 1 sheet (M.singleton (EdgeId 4) (-(2 * pi / 3))))
      forM_ [h | h <- hinges, hingeRole h /= PanelBend] $ \h -> do
        hingeRest h `shouldBe` (-(2 * pi / 3))
        angleOf (refinedMesh refined) h >>= (`shouldSatisfy` (\a -> abs (a + pi / 3) < 1e-12))
  it "keeps flat face divisions and triangulation diagonals as panel bends" $ do
    sheet <- starting diagonal {edgesAssignment = replicate 4 Border ++ [Flat]} (replicate 5 0)
    (_, hinges) <- right (buildSurfaceHinges defaultBending 2 sheet M.empty)
    map hingeRole hinges `shouldSatisfy` all (== PanelBend)
    buildSurfaceHinges defaultBending 2 sheet target `shouldBe` Left (UnexpectedRestAngle (EdgeId 4))
  it "rejects invalid signs, non-finite angles, extraneous controls and stiffness" $ do
    sheet <- starting diagonal [0, 0, 0, 0, 60]
    forM_ [-0.1, pi + 0.1, 0 / 0, 1 / 0] $ \angle ->
      buildSurfaceHinges defaultBending 1 sheet (M.singleton (EdgeId 4) angle) `shouldSatisfy` isLeft
    buildSurfaceHinges defaultBending 1 sheet (M.insert (EdgeId 0) 0 target) `shouldBe` Left (UnexpectedRestAngle (EdgeId 0))
    buildSurfaceHinges (Bending 0 1) 1 sheet target `shouldBe` Left InvalidBending
  it "refuses an active crease missing from the panel topology" $ do
    sheet <- right (surfaceFromFrame diagonal {facesVertices = [map VertexId [0, 1, 2, 3]]} >>= requireMaterialCoordinates)
    buildSurfaceHinges defaultBending 1 sheet target `shouldBe` Left (UnsupportedCrease (EdgeId 4))
  it "refuses two source creases claiming the same refined hinge" $ do
    let duplicated = diagonal {edgesVertices = edgesVertices diagonal ++ [(VertexId 0, VertexId 2)], edgesAssignment = edgesAssignment diagonal ++ [Valley]}
    sheet <- right (surfaceFromFrame duplicated >>= requireMaterialCoordinates)
    buildSurfaceHinges defaultBending 0 sheet (M.insert (EdgeId 5) (pi / 2) target) `shouldBe` Left (AmbiguousCreaseSegment 0 2)
  it "keeps coincident cut edges separate and gives them no spring" $ do
    let cut = emptyFrame {verticesCoords = [[0, 0], [1, 0], [0, 1], [0, 0], [1, 0], [0, 1]], facesVertices = [map VertexId [0, 1, 2], map VertexId [3, 4, 5]], edgesVertices = [(VertexId 0, VertexId 1), (VertexId 3, VertexId 4)], edgesAssignment = [Cut, Cut]}
    sheet <- right (surfaceFromFrame cut >>= requireMaterialCoordinates)
    (refined, hinges) <- right (buildSurfaceHinges defaultBending 1 sheet M.empty)
    componentCount (refinedMesh refined) `shouldBe` 2
    let ids eid = sort [i | (owner, (a, b)) <- refinedEdges refined, owner == eid, i <- [a, b]]
    [i | i <- ids (EdgeId 0), i `elem` ids (EdgeId 1)] `shouldBe` []
    map hingeRole hinges `shouldSatisfy` all (== PanelBend)
  forM_
    [ ("diagonal-cp", [0, 0, 0, 0, 60], [(EdgeId 4, 120)], [("base", V2 0.2 0.2), ("flap", V2 0.8 0.8)], [("base", "flap")]),
      ("kite-base", [0, 0, 0, 0, 0, 0, 75, 110], [(EdgeId 6, 150), (EdgeId 7, 165)], [("base", V2 0.6 0.6), ("right", V2 0.8 0.1), ("left", V2 0.1 0.8)], [("base", "right"), ("base", "left")])
    ]
    $ \(name, angles, rests, tags, orders) ->
      it ("solves " ++ name ++ " toward its known angles and independently checks endpoint contact") $ do
        source <- keyFrame <$> (loadFoldFile ("examples/" ++ name ++ ".fold") >>= right)
        let spec' = CaseSpec name "control" "" "" [] Nothing (Just (ContactSpec (V3 0 0 1) [PanelTag tag uv | (tag, uv) <- tags] orders))
        pose <- right (buildCasePose 0 spec' source (PoseSpec "start" angles))
        (refined, hinges) <- right (buildSurfaceHinges defaultBending 2 (poseSurface pose) (M.fromList [(eid, degrees * pi / 180) | (eid, degrees) <- rests]))
        let mesh = refinedMesh refined
        result <- right (relaxHinges defaultSettings hinges mesh)
        converged result `shouldBe` True
        final <- case reverse (checkpoints result) of point : _ -> pure (checkpointMesh point); [] -> fail "no checkpoints"
        triangles final `shouldBe` triangles mesh
        map sampleMaterial (samples final) `shouldBe` map sampleMaterial (samples mesh)
        componentCount final `shouldBe` 1
        maxLengthError final `shouldSatisfy` (< 1e-5)
        abs (areaRatio final - 1) `shouldSatisfy` (< 1e-5)
        forM_ hinges $ \h -> angleOf final h >>= (`shouldSatisfy` (\a -> abs (angleError a (hingeRest h)) < 1e-5))
        (crease, panel) <- right (bendingEnergy hinges final)
        crease `shouldSatisfy` (< 1e-10)
        panel `shouldSatisfy` (< 1e-10)
        (axis, requirements) <- maybe (fail "missing fixture orders") pure (surfaceLayerRequirements (poseSurface pose))
        report <- right (checkTriangleContact axis requirements (refinedPanels refined) final)
        report `shouldSatisfy` contactPassed
        checkedPanelPairs report `shouldBe` length (triangles mesh) * (length (triangles mesh) - 1) `div` 2
  it "reports crossing triangles even within one source panel" $ do
    let points = [V3 (-1) (-1) 0, V3 1 (-1) 0, V3 0 1 0, V3 0 (-0.5) (-1), V3 0 (-0.5) 1, V3 0 0.5 0]
        mesh = Mesh [materialSample 0 0 p | p <- points] [(0, 1, 2), (3, 4, 5)]
    report <- right (checkTriangleContact (V3 0 0 1) [] [FaceId 0, FaceId 0] mesh)
    crossingPanels report `shouldBe` [("triangle-0", "triangle-1")]
    contactPassed report `shouldBe` False
  it "does not quietly drop malformed triangle ownership or unknown layer declarations" $ do
    sheet <- starting diagonal [0, 0, 0, 0, 60]
    refined <- right (refineSurfaceWithEdges 0 sheet)
    checkTriangleContact (V3 0 0 1) [] [] (refinedMesh refined) `shouldSatisfy` isLeft
    checkTriangleContact (V3 0 0 1) [(FaceId 0, FaceId 99)] (refinedPanels refined) (refinedMesh refined) `shouldSatisfy` isLeft
  where
    target = M.singleton (EdgeId 4) (2 * pi / 3)

starting :: Frame -> [Double] -> IO (Surface V2)
starting source angles = right (foldFrameWith source {edgesFoldAngle = angles}) >>= right . surfaceFromFolded

angleOf :: MaterialMesh -> Hinge -> IO Double
angleOf mesh h = fst <$> right (hingeAngle h (IM.fromList (zip [0 ..] (samples mesh))))

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure

diagonal :: Frame
diagonal =
  emptyFrame
    { verticesCoords = [[0, 0], [1, 0], [1, 1], [0, 1]],
      edgesVertices = [(VertexId a, VertexId b) | (a, b) <- [(0, 1), (1, 2), (2, 3), (3, 0), (0, 2)]],
      edgesAssignment = replicate 4 Border ++ [Valley],
      facesVertices = [map VertexId [0, 1, 2], map VertexId [0, 2, 3]]
    }
