-- | Material identity must survive changes of pose, view and tessellation.
-- These tests use real folding outputs but check the surface's own contract,
-- including inputs whose missing material map must stay missing.
module Senbazuru.Origami.SurfaceSpec (spec) where

import Control.Monad (forM_)
import Data.Aeson (Value (..), toJSON)
import Data.Aeson.KeyMap qualified as KM
import Data.Either (isLeft)
import Data.List (nub, sort)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (Crease (..), frameVertices)
import Senbazuru.Fold.Types (Assignment (..), EdgeId (..), FaceId (..), FaceOrder (..), FoldFile (..), Frame (..), Stacking (..), VertexId (..), emptyFrame)
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Rigid (Rigid (..), identity, matIdentity, rotationAbout)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Folding (Folded (..), foldFrameWith)
import Senbazuru.Origami.Surface
import Test.Hspec
import Test.QuickCheck

spec :: Spec
spec = do
  describe "one material surface" $ do
    forM_ ["book-base", "quarter-fold", "square-base", "waterbomb-base", "bird-base"] $ \name ->
      it (name ++ " retains the cut pattern's material identities") $ do
        source <- fixture name
        folded <- requireRight (foldFrameWith source)
        sheet <- requireRight (surfaceFromFolded folded)
        let fr = surfaceFrame sheet
            original = foldedPattern folded
            actual = foldedFrame folded
        expected <- requireRight (frameVertices actual)
        map position (surfaceSamples sheet) `shouldBe` expected
        map sampleMaterial (surfaceSamples sheet) `shouldBe` [V2 u v | u : v : _ <- verticesCoords original]
        facesVertices fr `shouldBe` facesVertices actual
        edgesVertices fr `shouldBe` edgesVertices actual
        edgesAssignment fr `shouldBe` edgesAssignment actual
        edgesFoldAngle fr `shouldBe` edgesFoldAngle actual
        faceOrders fr `shouldBe` faceOrders actual
        surfaceThickness sheet `shouldBe` Nothing

    it "keeps touching quarters distinct instead of welding folded coordinates" $ do
      source <- fixture "quarter-fold"
      folded <- requireRight (foldFrameWith source)
      sheet <- requireRight (surfaceFromFolded folded)
      let ps = surfaceSamples sheet
      length ps `shouldBe` 9
      length (nub (map sampleMaterial ps)) `shouldBe` 9
      -- All four source corners land on the same folded corner. Their material
      -- ids remain distinct even though their positions agree to roundoff.
      let corners = [p | p <- ps, materialU p `elem` [0, 1], materialV p `elem` [0, 1]]
      length corners `shouldBe` 4
      [norm (position a ^-^ position b) | a <- corners, b <- corners] `shouldSatisfy` all (< 1e-12)

    it "uses the crossing cutter's new vertex rather than the original numbering" $ do
      source <- fixture "unit-square"
      folded <- requireRight (foldFrameWith source {edgesFoldAngle = replicate (length (edgesVertices source)) 0})
      sheet <- requireRight (surfaceFromFolded folded)
      length (surfaceSamples sheet) `shouldBe` length (verticesCoords source) + 1
      map sampleMaterial (surfaceSamples sheet) `shouldContain` [V2 0.5 0.5]
      surfaceFromFolded folded {foldedPattern = source} `shouldBe` Left SurfaceMaterialMismatch

    it "takes winding and face orders from the folded frame, not the material pattern" $ do
      source <- fixture "quarter-fold"
      folded <- requireRight (foldFrameWith source {facesVertices = map reverse (facesVertices source)})
      let order = FaceOrder (FaceId 0) (FaceId 1) Below
          placed = (foldedFrame folded) {faceOrders = [order]}
      sheet <- requireRight (surfaceFromFolded folded {foldedFrame = placed})
      facesVertices (surfaceFrame sheet) `shouldBe` facesVertices placed
      faceOrders (surfaceFrame sheet) `shouldBe` [order]

  describe "material coordinates are knowledge, not a projection" $ do
    it "knows an unfolded sheet's material coordinates" $ do
      sheet <- requireRight (surfaceFromFrame twoPanels >>= requireMaterialCoordinates)
      map sampleMaterial (surfaceSamples sheet) `shouldBe` [V2 0 0, V2 1 0, V2 1 1, V2 0 1]

    it "does not invent a material map for a flat folded frame" $ do
      source <- fixture "quarter-fold"
      folded <- requireRight (foldFrameWith source)
      sheet <- requireRight (surfaceFromFrame (foldedFrame folded))
      map sampleMaterial (surfaceSamples sheet) `shouldBe` replicate 9 Nothing
      requireMaterialCoordinates sheet `shouldBe` Left (SurfaceMissingMaterial (VertexId 0))

    it "round-trips the study's explicit material map through a folded FOLD frame" $ do
      source <- fixture "quarter-fold"
      folded <- requireRight (foldFrameWith source)
      sheet <- requireRight (surfaceFromFolded folded)
      moved <- requireRight (transformSurface (Rigid matIdentity (V3 2 3 4)) sheet)
      restored <- requireRight (surfaceFromFrame (materialFrame moved) >>= requireMaterialCoordinates)
      surfaceSamples restored `shouldBe` surfaceSamples moved
      facesVertices (surfaceFrame restored) `shouldBe` facesVertices (surfaceFrame moved)

    it "refuses malformed material metadata instead of guessing a replacement" $ do
      let withMaterial value = twoPanels {frameExtras = KM.singleton "senbazuru:material_coords" value}
      surfaceFromFrame (withMaterial (String "not a coordinate array")) `shouldBe` Left SurfaceInvalidMaterialCoordinates
      surfaceFromFrame (withMaterial (toJSON ([[0, 0]] :: [[Double]]))) `shouldBe` Left (SurfaceMaterialCount 4 1)
      surfaceFromFrame (withMaterial (toJSON ([[0], [1, 0], [1, 1], [0, 1]] :: [[Double]]))) `shouldBe` Left (SurfaceInvalidMaterialPoint (VertexId 0))

    it "does not mistake a raised crease-pattern frame for material in z = 0" $ do
      sheet <- requireRight (surfaceFromFrame twoPanels {verticesCoords = [[0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]]})
      requireMaterialCoordinates sheet `shouldBe` Left (SurfaceMissingMaterial (VertexId 0))

    it "refuses nonfinite geometry and mismatched material topology" $ do
      surfaceFromFrame twoPanels {verticesCoords = [[0 / 0, 0], [1, 0], [1, 1], [0, 1]]}
        `shouldBe` Left (SurfaceNonFinite (VertexId 0))
      source <- fixture "quarter-fold"
      folded <- requireRight (foldFrameWith source)
      surfaceFromFolded folded {foldedPattern = (foldedPattern folded) {edgesVertices = reverse (edgesVertices (foldedPattern folded))}}
        `shouldBe` Left SurfaceMaterialMismatch

  describe "refining within panels" $ do
    it "shares a crease midpoint and never turns numerical diagonals into creases" $ do
      folded <- requireRight (foldFrameWith twoPanels {edgesFoldAngle = [0, 0, 0, 0, 90]})
      sheet <- requireRight (surfaceFromFolded folded)
      (mesh, panels) <- requireRight (refineSurface 1 sheet)
      length (samples mesh) `shouldBe` 9
      length (triangles mesh) `shouldBe` 8
      sort panels `shouldBe` replicate 4 (FaceId 0) ++ replicate 4 (FaceId 1)
      let midpointIds = [i | (i, p) <- zip [0 ..] (samples mesh), sampleMaterial p == V2 0.5 0.5]
      length midpointIds `shouldBe` 1
      forM_ midpointIds $ \mid -> do
        let owners = nub [fid | ((a, b, c), fid) <- zip (triangles mesh) panels, mid `elem` [a, b, c]]
        sort owners `shouldBe` [FaceId 0, FaceId 1]
      features <- requireRight (surfaceFeatures sheet)
      length features `shouldBe` 5
      [(creaseId c, owners) | (c, owners) <- features, creaseAssignment c == Valley]
        `shouldBe` [(EdgeId 4, [FaceId 0, FaceId 1])]

    it "does not join distinct vertex ids just because their material coordinates coincide" $ do
      let cut = emptyFrame {verticesCoords = [[0, 0], [1, 0], [0, 1], [0, 0], [1, 0], [0, 1]], facesVertices = [map VertexId [0, 1, 2], map VertexId [3, 4, 5]], edgesVertices = [(VertexId 0, VertexId 1), (VertexId 3, VertexId 4)], edgesAssignment = [Cut, Cut]}
      sheet <- requireRight (surfaceFromFrame cut >>= requireMaterialCoordinates)
      (mesh, panels) <- requireRight (refineSurface 1 sheet)
      length (samples mesh) `shouldBe` 12
      let verticesOf fid = nub [v | ((a, b, c), owner) <- zip (triangles mesh) panels, owner == fid, v <- [a, b, c]]
      [v | v <- verticesOf (FaceId 0), v `elem` verticesOf (FaceId 1)] `shouldBe` []

    it "retains unassigned and cut features, and refuses to weld an unsplit slit" $ do
      forM_ [Unassigned, Cut] $ \assignment -> do
        sheet <- requireRight (surfaceFromFrame twoPanels {edgesAssignment = replicate 4 Border ++ [assignment]} >>= requireMaterialCoordinates)
        features <- requireRight (surfaceFeatures sheet)
        map (creaseAssignment . fst) features `shouldBe` replicate 4 Border ++ [assignment]
        if assignment == Cut
          then refineSurface 1 sheet `shouldBe` Left (SurfaceJoinedCut (EdgeId 4))
          else do
            (mesh, _) <- requireRight (refineSurface 1 sheet)
            length (triangles mesh) `shouldBe` 8

    it "preserves material edge lengths at arbitrary hinge angles and refinements" $
      forAll (choose (-175, 175)) $ \angle ->
        forAll (chooseInt (0, 3)) $ \level ->
          case do
            folded <- firstString (foldFrameWith twoPanels {edgesFoldAngle = [0, 0, 0, 0, angle]})
            sheet <- firstString (surfaceFromFolded folded)
            firstString (refineSurface level sheet) of
            Left err -> counterexample err False
            Right (mesh, _) ->
              let points = zip [0 ..] (samples mesh)
                  errors = [abs (norm (position p ^-^ position q) - norm (sampleMaterial p ^-^ sampleMaterial q)) | (a, b, c) <- triangles mesh, (i, j) <- [(a, b), (b, c), (c, a)], Just p <- [lookup i points], Just q <- [lookup j points]]
               in counterexample (show (maximum (0 : errors))) (all (< 1e-12) errors)

    it "refuses unsupported subdivision levels and concave panels" $ do
      sheet <- requireRight (surfaceFromFrame twoPanels >>= requireMaterialCoordinates)
      refineSurface (-1) sheet `shouldBe` Left (SurfaceBadRefinement (-1))
      refineSurface 6 sheet `shouldBe` Left (SurfaceBadRefinement 6)
      concave <- requireRight (surfaceFromFrame emptyFrame {verticesCoords = [[0, 0], [2, 0], [0.5, 0.5], [0, 2]], facesVertices = [map VertexId [0, 1, 2, 3]]} >>= requireMaterialCoordinates)
      refineSurface 0 concave `shouldBe` Left (SurfaceNonConvex (FaceId 0))

    it "keeps convexity decisions relative to the model's units" $ do
      forM_ [1e-8, 1, 1e8] $ \unitScale -> do
        let scaled fr = fr {verticesCoords = map (map (* unitScale)) (verticesCoords fr)}
        sheet <- requireRight (surfaceFromFrame (scaled twoPanels) >>= requireMaterialCoordinates)
        (mesh, _) <- requireRight (refineSurface 1 sheet)
        length (triangles mesh) `shouldBe` 8
        concave <- requireRight (surfaceFromFrame (scaled emptyFrame {verticesCoords = [[0, 0], [2, 0], [0.5, 0.5], [0, 2]], facesVertices = [map VertexId [0, 1, 2, 3]]}) >>= requireMaterialCoordinates)
        refineSurface 0 concave `shouldBe` Left (SurfaceNonConvex (FaceId 0))

    it "refuses a degenerate fan instead of producing a zero-area mesh triangle" $ do
      let collinear = emptyFrame {verticesCoords = [[0, 0], [0.5, 0], [1, 0], [1, 1], [0, 1]], facesVertices = [map VertexId [0, 1, 2, 3, 4]]}
      sheet <- requireRight (surfaceFromFrame collinear >>= requireMaterialCoordinates)
      refineSurface 0 sheet `shouldBe` Left (SurfaceDegenerateFan (FaceId 0))

  describe "material properties and layer requirements" $ do
    it "stores optional thickness without moving vertices or changing topology" $ do
      sheet <- requireRight (surfaceFromFrame twoPanels)
      thick <- requireRight (withPhysicalThickness (Just 0.001) sheet)
      surfaceThickness thick `shouldBe` Just 0.001
      surfaceFrame thick `shouldBe` surfaceFrame sheet
      withPhysicalThickness Nothing thick `shouldBe` Right sheet
      withPhysicalThickness (Just (-1)) sheet `shouldBe` Left (SurfaceBadThickness (-1))
      withPhysicalThickness (Just (1 / 0)) sheet `shouldSatisfy` isLeft

    it "rotates directional requirements with the paper and preserves material coordinates" $ do
      sheet <- requireRight (surfaceFromFrame twoPanels >>= requireMaterialCoordinates)
      ordered <- requireRight (withLayerRequirements (V3 0 0 1) [(FaceId 0, FaceId 1)] sheet >>= withFaceOrders [FaceOrder (FaceId 0) (FaceId 1) Below])
      moved <- requireRight (transformSurface (rotationAbout (V3 0 0 0) (V3 1 0 0) pi) ordered)
      (axis, pairs) <- maybe (fail "lost the layer requirements during rotation") pure (surfaceLayerRequirements moved)
      norm (axis ^-^ V3 0 0 (-1)) `shouldSatisfy` (< 1e-12)
      pairs `shouldBe` [(FaceId 0, FaceId 1)]
      faceOrders (surfaceFrame moved) `shouldBe` faceOrders (surfaceFrame ordered)
      map sampleMaterial (surfaceSamples moved) `shouldBe` map sampleMaterial (surfaceSamples ordered)
      transformSurface identity ordered `shouldBe` Right ordered

    it "validates requirements and transformed positions" $ do
      sheet <- requireRight (surfaceFromFrame twoPanels)
      withLayerRequirements (V3 0 0 0) [] sheet `shouldBe` Left (SurfaceBadDirection (V3 0 0 0))
      withLayerRequirements (V3 0 0 1) [(FaceId 0, FaceId 0)] sheet `shouldBe` Left (SurfaceBadLayerPair (FaceId 0) (FaceId 0))
      withLayerRequirements (V3 0 0 1) [(FaceId 0, FaceId 2)] sheet `shouldBe` Left (SurfaceBadLayerPair (FaceId 0) (FaceId 2))
      transformSurface (Rigid matIdentity (V3 (0 / 0) 0 0)) sheet `shouldBe` Left (SurfaceNonFinite (VertexId 0))

    it "updates a declared coordinate dimension when a sheet is tilted" $ do
      sheet <- requireRight (surfaceFromFrame twoPanels {frameAttributes = ["2D", "orientable"]})
      moved <- requireRight (transformSurface (rotationAbout (V3 0 0 0) (V3 1 0 0) (pi / 2)) sheet)
      frameAttributes (surfaceFrame moved) `shouldBe` ["3D", "orientable"]

    it "preserves vendor metadata on reading and discards it when geometry changes" $ do
      let extras = KM.singleton "vendor:geometry" (String "belongs to the original positions")
      sheet <- requireRight (surfaceFromFrame twoPanels {frameExtras = extras})
      frameExtras (surfaceFrame sheet) `shouldBe` extras
      moved <- requireRight (transformSurface (Rigid matIdentity (V3 1 2 3)) sheet)
      frameExtras (surfaceFrame moved) `shouldBe` mempty

fixture :: String -> IO Frame
fixture name = keyFrame <$> (loadFoldFile ("examples/" ++ name ++ ".fold") >>= requireRight)

requireRight :: (Show e) => Either e a -> IO a
requireRight = either (fail . show) pure

firstString :: (Show e) => Either e a -> Either String a
firstString = either (Left . show) Right

twoPanels :: Frame
twoPanels =
  emptyFrame
    { verticesCoords = [[0, 0], [1, 0], [1, 1], [0, 1]],
      edgesVertices = [(VertexId a, VertexId b) | (a, b) <- [(0, 1), (1, 2), (2, 3), (3, 0), (0, 2)]],
      edgesAssignment = [Border, Border, Border, Border, Valley],
      facesVertices = [map VertexId [0, 1, 2], map VertexId [0, 2, 3]]
    }
