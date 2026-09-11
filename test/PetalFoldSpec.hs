-- | A petal fold lifts one tip of the square base while its two sides fold
-- inward. Seven crease angles change together: four side folds close, two
-- old folds open, and the tip turns about its hinge. Choosing those angles
-- independently would tear the paper. See docs/notes/petal-fold-motion.md.
--
-- The body stays flat, making layer order essential even while the petal is
-- in the air. Tests check both flat endpoints against the production stacking
-- solver, and all panel pairs along sampled motion. This does not certify
-- continuous collision freedom or a finite-thickness sheet.
module PetalFoldSpec (spec) where

import Control.Monad (forM_)
import Data.Aeson (eitherDecode)
import Data.ByteString.Lazy qualified as BL
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.List (find)
import Data.Set qualified as S
import FoldMaterial
import PanelContact
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (Face (..), frameFaces, frameVertices)
import Senbazuru.Fold.Types (FaceId (..), FaceOrder (..), Frame (..), Stacking (..), VertexId (..), keyFrame)
import Senbazuru.Geometry.Rigid (applyRigid)
import Senbazuru.Geometry.V3 (V3 (..), polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Folding
import Senbazuru.Origami.Stacking (defaultBudget, solveStacking, stackingSpace, stateCount)
import StudyCase
import Test.Hspec
import Test.QuickCheck

spec :: Spec
spec = describe "first petal motion" $ do
  cases <- runIO $ BL.readFile "study/fold-material/cases.json" >>= requireRight . eitherDecode
  entry <- runIO $ requireJust (find ((== "bird-petal") . caseId) (cases :: [CaseSpec]))
  source <- runIO $ keyFrame <$> (loadFoldFile (caseSource entry) >>= requireRight)
  let at level t = requireRight (buildCasePose level entry source (PoseSpec "petal" (petalAngles t)))
  it "records eight compatible states from the square base through a nearly closed first petal" $ do
    caseSource entry `shouldBe` "examples/bird-base.fold"
    caseFixedPanel entry `shouldBe` Just (0.58, 0.4)
    length (caseSteps entry) `shouldBe` 8
    forM_ (zip (caseSteps entry) [0, 15, 30, 60, 90, 120, 150, 175]) $ \(step, t) -> do
      length (poseAngles step) `shouldBe` 28
      zipWith (-) (poseAngles step) (petalAngles t) `shouldSatisfy` all ((< 1e-12) . abs)
  it "preserves material and contact at arbitrary compatible angles and refinements" $
    forAll (choose (0.01, 179.99)) $ \t ->
      forAll (chooseInt (0, 2)) $ \level ->
        case buildCasePose level entry source (PoseSpec "sample" (petalAngles t)) of
          Left err -> counterexample (show err) False
          Right pose ->
            let mesh = poseMesh pose
             in counterexample (show (poseContact pose)) $
                  componentCount mesh == 1
                    && all ((< 1e-12) . abs) (edgeStrains mesh)
                    && abs (areaRatio mesh - 1) < 1e-12
                    && poseContact pose == Just (ContactCheck 120 [] [] [] [])
  it "checks all 120 panel pairs in a half-degree sweep including both flat endpoints" $
    forM_ [0, 0.5 .. 180] $ \t -> do
      pose <- at 0 t
      poseContact pose `shouldBe` Just (ContactCheck 120 [] [] [] [])
  it "agrees at every shared vertex and achieves angles measured independently from panel normals" $
    forM_ [0, 15, 30, 60, 90, 120, 150, 175, 180] $ \t -> do
      result <- requireRight (foldFrameWith source {edgesFoldAngle = petalAngles t})
      let sheet = foldedPattern result
          final = foldedFrame result
      original <- IM.fromList . zip [0 ..] <$> requireRight (frameVertices sheet)
      placed <- IM.fromList . zip [0 ..] <$> requireRight (frameVertices final)
      forM_ (zip [0 ..] (facesVertices sheet)) $ \(i, vertices) -> do
        transform <- requireJust (IM.lookup i (foldedPlacements result))
        forM_ vertices $ \(VertexId v) -> do
          p <- requireJust (IM.lookup v original)
          q <- requireJust (IM.lookup v placed)
          norm (applyRigid transform p ^-^ q) `shouldSatisfy` (< 1e-12)
      faces <- requireRight (frameFaces final)
      forM_ (zip (edgesVertices sheet) (edgesFoldAngle sheet)) $ \((a, b), degrees) ->
        case [face | face <- faces, a `elem` faceVertexIds face, b `elem` faceVertexIds face] of
          [_] -> pure ()
          [left, right] -> do
            let normal face = let n = polygonNormal (faceCorners face) in (1 / norm n) *^ n
            abs (dot (normal left) (normal right) - cos (degrees * pi / 180)) `shouldSatisfy` (< 1e-12)
          _ -> expectationFailure "edge must border one or two panels"
  it "lifts the tip on a half-unit circle and keeps the body and second petal fixed" $ do
    resting <- at 2 0
    -- Faces 0--3 and 13 form the first petal and its two sides. Every other
    -- material panel belongs to the stationary packet. Refinement checks its
    -- interiors too, not only the original corners.
    let moving = [0, 1, 2, 3, 13]
        fixedIndices = S.toList $ S.fromList [i | ((a, b, c), panel) <- zip (triangles (poseMesh resting)) (posePanels resting), panel `notElem` moving, i <- [a, b, c]]
        indexed = IM.fromList (zip [0 ..] (samples (poseMesh resting)))
    forM_ [0, 15, 30, 60, 90, 120, 150, 175, 180] $ \t -> do
      pose <- at 2 t
      let mesh = poseMesh pose
          radians = t * pi / 180
          d = 1 / sqrt 2
          expected = V3 ((2 - d + d * cos radians) / 2) ((d - d * cos radians) / 2) (sin radians / 2)
      -- The hinge midpoint is (1-d/2,d/2): turning the original corner
      -- (1,0) around it gives a radius of 1/2 in the perpendicular plane.
      tip <- pointAt (1, 0) mesh
      norm (tip ^-^ expected) `shouldSatisfy` (< 1e-12)
      forM_ fixedIndices $ \i -> do
        p <- requireJust (IM.lookup i indexed)
        q <- pointAt (materialU p, materialV p) mesh
        norm (position p ^-^ q) `shouldSatisfy` (< 1e-12)
  it "starts from the same square-base landmarks and lifts only SE at the exact endpoint" $ do
    start <- at 0 0
    end <- at 0 180
    let d = 1 / sqrt 2
        r = 1 - d
    forM_ [(0, 0), (1, 0), (1, 1), (0, 1)] $ \uv ->
      pointAt uv (poseMesh start) >>= \p -> norm (p ^-^ V3 1 0 0) `shouldSatisfy` (< 1e-12)
    forM_ [(0, 0), (1, 1), (0, 1)] $ \uv ->
      pointAt uv (poseMesh end) >>= \p -> norm (p ^-^ V3 1 0 0) `shouldSatisfy` (< 1e-12)
    tip <- pointAt (1, 0) (poseMesh end)
    norm (tip ^-^ V3 r d 0) `shouldSatisfy` (< 1e-12)
    forM_ [(0.5, 0), (1, 0.5)] $ \uv -> do
      shoulder <- pointAt uv (poseMesh end)
      norm (shoulder ^-^ V3 ((1 + r) / 2) (d / 2) 0) `shouldSatisfy` (< 1e-12)
    -- Completing the other symmetric petal recovers the already verified
    -- bird endpoint's angles. The current gallery intentionally stops first.
    let secondEdges = [19, 20, 21, 23, 24, 25, 27]
        complete = [if i `elem` secondEdges then final else first | (i, first, final) <- zip3 [0 :: Int ..] (petalAngles 180) (edgesFoldAngle source)]
    complete `shouldBe` edgesFoldAngle source
  forM_ [0, 180] $ \t -> it ("agrees with the unique flat stacking at hinge " ++ show t) $ do
    pose <- at 0 t
    result <- requireRight (foldFrameWith source {edgesFoldAngle = petalAngles t})
    let coords (V3 x y z) = [x, y, z]
        final = (foldedFrame result) {verticesCoords = map (coords . position) (samples (poseMesh pose))}
    space <- requireRight (stackingSpace defaultBudget final)
    stateCount space `shouldBe` (1, False)
    orders <- requireRight (solveStacking final)
    faces <- requireRight (frameFaces final)
    (_, relations) <- requireJust (poseOrders pose)
    let declared = transitive (S.fromList relations)
    forM_ orders $ \(FaceOrder a b stacking) -> do
      face <- requireJust (find ((== b) . faceId) faces)
      let V3 _ _ z = polygonNormal (faceCorners face)
          pair = if (stacking == Above) == (z > 0) then (unFaceId b, unFaceId a) else (unFaceId a, unFaceId b)
      abs z `shouldSatisfy` (> 1e-12)
      pair `shouldSatisfy` (`S.member` declared)
    -- Missing order remains a failure even when there are no 3D crossings.
    let without = entry {caseContact = fmap (\c -> c {panelOrders = []}) (caseContact entry)}
    unchecked <- requireRight (buildCasePose 0 without source (PoseSpec "unordered" (petalAngles t)))
    report <- requireJust (poseContact unchecked)
    crossingPanels report `shouldBe` []
    unorderedContacts report `shouldSatisfy` (not . null)
  it "keeps the anchor on the stationary panel even after edge renumbering" $ do
    let reordered = source {edgesVertices = reverse (edgesVertices source), edgesAssignment = reverse (edgesAssignment source)}
    expected <- at 0 90
    actual <- requireRight (buildCasePose 0 entry reordered (PoseSpec "reordered" (reverse (petalAngles 90))))
    forM_ (samples (poseMesh expected)) $ \p -> do
      q <- pointAt (materialU p, materialV p) (poseMesh actual)
      norm (position p ^-^ q) `shouldSatisfy` (< 1e-12)
  it "associates each feature edge with its incident material panels" $ do
    forM_ [0, 90, 180] $ \t -> do
      pose <- at 0 t
      length (poseLinePanels pose) `shouldBe` length (poseLines pose)
      let faces = IM.fromList [(i, map position ps) | (i, ps) <- poseFaces pose]
      forM_ (zip (poseLines pose) (poseLinePanels pose)) $ \((a, b), owners) -> do
        length owners `shouldSatisfy` (\n -> n == 1 || n == 2)
        forM_ owners $ \i -> do
          corners <- requireJust (IM.lookup i faces)
          corners `shouldSatisfy` any (\p -> norm (p ^-^ a) < 1e-12)
          corners `shouldSatisfy` any (\p -> norm (p ^-^ b) < 1e-12)
      -- There are eight boundary edges. All four source guides bend
      -- initially; only the front pair becomes flat at t = 180.
      length (poseLines pose) `shouldBe` (if t == 180 then 26 else 28)
  it "retains the same resolved order declarations when contact fails" $ do
    good <- at 0 90
    bad <- requireRight (buildCasePose 0 entry source (PoseSpec "wrong side" (map negate (petalAngles 90))))
    poseOrders bad `shouldBe` poseOrders good
    poseContact bad `shouldSatisfy` maybe False (not . contactPassed)
  it "rejects ambiguous, outside and non-finite material anchors" $
    forM_ [(0, 0), (0.5, 0.5), (2, 2), (0 / 0, 0.4), (0.58, 1 / 0)] $ \anchor ->
      buildCasePose 0 entry {caseFixedPanel = Just anchor} source (PoseSpec "bad anchor" (petalAngles 90)) `shouldSatisfy` isLeft
  it "refuses independent side-fold changes and uniform interpolation from the square base" $ do
    let changed = [if i == (12 :: Int) then a + 1 else a | (i, a) <- zip [0 ..] (petalAngles 90)]
        halfway = zipWith (\a b -> (a + b) / 2) (petalAngles 0) (petalAngles 180)
    buildPose 0 source (PoseSpec "one wrong side" changed) `shouldSatisfy` isLeft
    buildPose 0 source (PoseSpec "linear angles" halfway) `shouldSatisfy` isLeft

-- | Let t be the petal hinge angle. Each side magnitude s obeys
-- tan(s/2) = sin(pi/8) * tan(t/2); atan2 stays defined at 180 degrees.
-- The two outer midline folds open from -180 to zero, rather than closing.
petalAngles :: Double -> [Double]
petalAngles t =
  let h = t * pi / 360
      s = 360 / pi * atan2 (sin (pi / 8) * sin h) (cos h)
   in replicate 8 0 ++ [180, 180, -180, t - 180, -s, -s, -180, t - 180, -s, -s, -180, -180, 0, 0, -180, -180, 0, 0, t, 0]

transitive :: (Ord a) => S.Set (a, a) -> S.Set (a, a)
transitive pairs =
  let extended = S.union pairs (S.fromList [(a, d) | (a, b) <- S.toList pairs, (c, d) <- S.toList pairs, b == c])
   in if pairs == extended then pairs else transitive extended

pointAt :: (Double, Double) -> Mesh -> IO V3
pointAt (u, v) mesh = position <$> requireJust (find (\p -> abs (materialU p - u) < 1e-12 && abs (materialV p - v) < 1e-12) (samples mesh))

requireRight :: (Show e) => Either e a -> IO a
requireRight (Left err) = expectationFailure (show err) >> fail "petal failed"
requireRight (Right value) = pure value

requireJust :: Maybe a -> IO a
requireJust Nothing = expectationFailure "missing petal fixture element" >> fail "petal failed"
requireJust (Just value) = pure value
