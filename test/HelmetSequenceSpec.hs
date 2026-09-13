-- | An entire authored route, independently measured at and between joins.
-- The sweep checks whole turns; these sampled checks additionally verify
-- exported material geometry, achieved angles and the carried layer orders.
module HelmetSequenceSpec (spec) where

import Control.Monad (forM_)
import Data.Aeson (eitherDecode, encode)
import Data.Either (isLeft)
import Data.IntMap.Strict qualified as IM
import Data.List (nub)
import Data.Text qualified as T
import HelmetGallery (helmetSvg)
import HelmetSequence
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (Face (..), frameFaces, frameVertices, ringEdges)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2)
import Senbazuru.Geometry.Rigid (applyRigid, inverse)
import Senbazuru.Geometry.V3 (V3 (..), cross, polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Flap
import Senbazuru.Origami.Folding
import Senbazuru.Origami.HingeSweep
import Senbazuru.Origami.Surface
import Test.Golden (goldenText)
import Test.Hspec

spec :: Spec
spec = describe "checked helmet sequence" $ do
  source <- runIO (loadFoldFile "examples/helmet-base.fold" >>= right)
  moves <- runIO (right (buildHelmetSequence (keyFrame source)))
  states <- runIO (right (helmetStates moves))
  it "rejects empty, duplicate, incomplete, non-boundary and bent hinge selections" $ do
    opening <- require "initial move" (case moves of m : _ -> Just m; [] -> Nothing)
    let start = helmetStart opening
        prepare ids side = prepareFlapAlong (map EdgeId ids) (FaceId side) 90 start
    prepare [] 5 `shouldSatisfy` (\case Left FlapEmptyHinge -> True; _ -> False)
    prepare [8, 8] 5 `shouldSatisfy` (\case Left (FlapDuplicateCrease (EdgeId 8)) -> True; _ -> False)
    prepare [8] 5 `shouldSatisfy` (\case Left FlapCoupled {} -> True; _ -> False)
    prepare [8, 9, 10, 12] 5 `shouldSatisfy` (\case Left FlapNotBoundary {} -> True; _ -> False)
    prepare [8, 10] 1 `shouldSatisfy` (\case Left (FlapUnalignedCrease (EdgeId 10)) -> True; _ -> False)
    prepare [8, 99] 5 `shouldSatisfy` (\case Left (FlapMissingCrease (EdgeId 99)) -> True; _ -> False)
    prepare [8, 0] 5 `shouldSatisfy` (\case Left (FlapNotHinge (EdgeId 0)) -> True; _ -> False)
    prepare [8, 9] 0 `shouldSatisfy` (\case Left FlapWrongSide {} -> True; _ -> False)

  it "does not infer permission for stacked contact from coincident positions" $ do
    corner <- require "first corner move" (case drop 1 moves of m : _ -> Just m; [] -> Nothing)
    let original = helmetStart corner
    start <- right (foldFrameWith (foldedPattern original) {edgesFoldAngle = edgesFoldAngle (foldedFrame original), faceOrders = []})
    (prepareFlapAlong [EdgeId 10, EdgeId 12] (FaceId 1) 180 start >>= checkFlap defaultSweepSettings) `shouldSatisfy` isLeft

  it "uses the first segment's angle convention, independently of stored endpoint direction" $ do
    corner <- require "first corner move" (case drop 1 moves of m : _ -> Just m; [] -> Nothing)
    let original = helmetStart corner
    start <- right (foldFrameWith (foldedPattern original) {edgesFoldAngle = edgesFoldAngle (foldedFrame original), faceOrders = faceOrders (foldedFrame original), edgesVertices = map (\(a, b) -> (b, a)) (edgesVertices (foldedPattern original))})
    -- Segment 12 is on the upside-down layer: choosing it first reverses
    -- the sign of the supplied travel, but not the physical motion.
    motion <- right (prepareFlapAlong [EdgeId 12, EdgeId 10] (FaceId 5) (-180) start >>= checkFlap defaultSweepSettings)
    forM_ [0, 0.25, 0.5, 0.75, 1] $ \t -> do
      originalPose <- right (flapAt (helmetMotion corner) t)
      reversedPose <- right (flapAt motion t)
      edgesFoldAngle (surfaceFrame reversedPose) `shouldBe` edgesFoldAngle (surfaceFrame originalPose)
      zipWith (\a b -> norm (position a ^-^ position b)) (surfaceSamples originalPose) (surfaceSamples reversedPose) `shouldSatisfy` all (< 1e-12)

  forM_ [1e-5, 1, 1e5] $ \scale ->
    forM_ [False, True] $ \backwards ->
      it ("checks the whole route at scale " ++ show scale ++ " with reversed winding " ++ show backwards) $ do
        let original = keyFrame source
            input = original {verticesCoords = map (map (* scale)) (verticesCoords original), facesVertices = map (if backwards then reverse else id) (facesVertices original)}
        route <- right (buildHelmetSequence input)
        map (sweepOutcome . flapCheck . helmetMotion) route `shouldBe` replicate 3 SweepClear
        forM_ route $ \move -> forM_ [0, 0.37, 0.5, 0.83, 1] $ \t -> do
          surface <- right (flapAt (helmetMotion move) t)
          materialError surface `shouldSatisfy` (< 1e-12)

  it "completes the diagonal and both doubled corners with opposite signs on upside-down layers" $ do
    length moves `shouldBe` 3
    length states `shouldBe` 7
    map (sweepOutcome . flapCheck . helmetMotion) moves `shouldBe` replicate 3 SweepClear
    map (flapMovingFaces . helmetMotion) moves `shouldBe` map (map FaceId) [[3, 4, 5], [1, 5], [2, 3]]
    map (edgesFoldAngle . surfaceFrame . helmetEnd) moves
      `shouldBe` map (replicate 8 0 ++) [[180, 180, 0, 0, 0, 0], [180, 180, 180, 0, -180, 0], [180, 180, 180, -180, -180, 180]]
    map (length . faceOrders . surfaceFrame . helmetEnd) moves `shouldBe` [3, 7, 11]

  forM_ (zip [1 :: Int ..] moves) $ \(i, move) ->
    it ("preserves lengths, shared corners, signed crease angles and contact throughout move " ++ show i) $ do
      material <- right (frameVertices (foldedPattern (helmetStart move)))
      let materialPoints = zip (map VertexId [0 ..]) material
          originalTopology = facesVertices (foldedPattern (helmetStart move))
      forM_ [0, 0.1 .. 1] $ \t -> do
        sheet <- right (flapAt (helmetMotion move) t)
        let fr = surfaceFrame sheet
        facesVertices fr `shouldBe` originalTopology
        length (surfaceSamples sheet) `shouldBe` 9
        materialError sheet `shouldSatisfy` (< 1e-12)
        points <- right (frameVertices fr)
        let placed = zip (map VertexId [0 ..]) points
        -- Independently place each face's copy of each vertex. All copies
        -- must meet at the one position exported for that material id.
        folded <- right (foldFrameWith (foldedPattern (helmetStart move)) {edgesFoldAngle = edgesFoldAngle fr, faceOrders = faceOrders fr})
        forM_ (zip (map FaceId [0 ..]) originalTopology) $ \(fid, ring) -> do
          transform <- require "face transform" (IM.lookup (unFaceId fid) (foldedPlacements folded))
          forM_ ring $ \vid -> do
            p <- require "material vertex" (lookup vid materialPoints)
            q <- require "placed vertex" (lookup vid placed)
            norm (applyRigid transform p ^-^ q) `shouldSatisfy` (< 1e-12)
        faces <- right (frameFaces fr)
        centre <- require "central face" (lookup (FaceId 0) [(faceId f, f) | f <- faces])
        forM_ (faceVertexIds centre) $ \vid -> do
          p <- require "central material vertex" (lookup vid materialPoints)
          q <- require "central placed vertex" (lookup vid placed)
          norm (p ^-^ q) `shouldSatisfy` (< 1e-12)
        forM_ (zip (map EdgeId [0 ..]) (zip (edgesVertices fr) (edgesFoldAngle fr))) $ \(eid, ((a, b), requested)) ->
          if unEdgeId eid < 8
            then pure ()
            else do
              let incident = [f | f <- faces, a `elem` faceVertexIds f, b `elem` faceVertexIds f]
              (fixed, corner) <- case incident of
                [f, g] -> pure (f, g)
                _ -> fail "crease must join two faces"
              let oriented = if (a, b) `elem` ringEdges (faceVertexIds fixed) then (a, b) else (b, a)
              from <- require "hinge start" (lookup (fst oriented) placed)
              to <- require "hinge end" (lookup (snd oriented) placed)
              let axis = unit (to ^-^ from)
                  fixedNormal = unit (polygonNormal (faceCorners fixed))
                  movingNormal = unit (polygonNormal (faceCorners corner))
                  measured = negate (180 / pi * atan2 (dot axis (cross fixedNormal movingNormal)) (dot fixedNormal movingNormal))
                  difference = measured - requested
              minimum (map abs [difference, difference - 360, difference + 360]) `shouldSatisfy` (< 1e-9)
        -- Check each pair in the second panel's plane. A touching stack can
        -- be upright halfway through a turn, where world-z order is undefined.
        forM_ [(f, g) | f <- faces, g <- faces, faceId f < faceId g] $ \(f, g) -> do
          let pairOrders = [o | o <- faceOrders fr, (orderFace o == faceId f && orderRelativeTo o == faceId g) || (orderFace o == faceId g && orderRelativeTo o == faceId f)]
          (direction, ordered) <- case pairOrders of
            [] -> pure (V3 0 0 1, [])
            o : _ -> do
              relative <- require "order-relative panel" (lookup (orderRelativeTo o) [(faceId h, h) | h <- faces])
              pure (unit (polygonNormal (faceCorners relative)), [if orderStacking o == Above then (name (orderRelativeTo o), name (orderFace o)) else (name (orderFace o), name (orderRelativeTo o))])
          report <- right (checkPanelContact direction ordered [Panel (name (faceId h)) (faceCorners h) | h <- [f, g]])
          contactPassed report `shouldBe` True

  it "carries exactly the accepted positions, material ids, angles and orders across each join" $
    forM_ (zip moves (drop 1 moves)) $ \(previous, following) -> do
      start <- right (flapAt (helmetMotion following) 0)
      let end = helmetEnd previous
      faceOrders (surfaceFrame start) `shouldMatchList` faceOrders (surfaceFrame end)
      edgesFoldAngle (surfaceFrame start) `shouldBe` edgesFoldAngle (surfaceFrame end)
      map sampleMaterial (surfaceSamples start) `shouldBe` map sampleMaterial (surfaceSamples end)
      zipWith (\a b -> norm (position a ^-^ position b)) (surfaceSamples start) (surfaceSamples end) `shouldSatisfy` all (< 1e-12)

  it "matches the existing base and independently places all four corners at the fixed tip" $ do
    completed <- require "completed base" (case drop 2 moves of m : _ -> Just (helmetEnd m); [] -> Nothing)
    reference <- right (foldFrameWith (keyFrame source))
    centreTransform <- require "reference central transform" (IM.lookup 1 (foldedPlacements reference))
    expected <- map (applyRigid (inverse centreTransform)) <$> right (frameVertices (foldedFrame reference))
    actual <- right (frameVertices (surfaceFrame completed))
    length actual `shouldBe` length expected
    zipWith (\a b -> norm (a ^-^ b)) actual expected `shouldSatisfy` all (< 1e-12)
    let landmarks = replicate 4 (V3 1 0 0) ++ [V3 0.5 0 0, V3 0.5 0.5 0, V3 1 0.5 0, V3 0.5 0 0, V3 1 0.5 0]
    zipWith (\a b -> norm (a ^-^ b)) actual landmarks `shouldSatisfy` all (< 1e-12)
    length (nub (map sampleMaterial (take 4 (surfaceSamples completed)))) `shouldBe` 4

  it "reopens a doubled corner on its accepted side and refuses the identical endpoint reached through the body" $ do
    closed <- require "first corner endpoint" (case drop 1 moves of m : _ -> Just (helmetEnd m); [] -> Nothing)
    initial <- require "first corner material" (case drop 1 moves of m : _ -> Just (helmetStart m); [] -> Nothing)
    let accepted = surfaceFrame closed
    start <- right (foldFrameWith (foldedPattern initial) {edgesFoldAngle = edgesFoldAngle accepted, faceOrders = faceOrders accepted})
    motion <- right (prepareFlapAlong [EdgeId 10, EdgeId 12] (FaceId 1) (-180) start >>= checkFlap defaultSweepSettings)
    end <- right (flapAt motion 1)
    edgesFoldAngle (surfaceFrame end) `shouldBe` replicate 8 0 ++ [180, 180, 0, 0, 0, 0]
    wrong <- right (prepareFlapAlong [EdgeId 10, EdgeId 12] (FaceId 1) 180 start)
    case checkFlap defaultSweepSettings wrong of
      Left FlapEndpointOrder {} -> pure ()
      other -> expectationFailure (show other)

  it "round-trips the illustrated states with their material coordinates and orders" $ do
    let file = helmetFile states
    eitherDecode (encode file) `shouldBe` Right file
    forM_ (zip (otherFrames file) states) $ \(fr, (_, original)) -> do
      reloaded <- right (surfaceFromFrame fr)
      map sampleMaterial (surfaceSamples reloaded) `shouldBe` map (Just . sampleMaterial) (surfaceSamples original)
      faceOrders (surfaceFrame reloaded) `shouldBe` faceOrders (surfaceFrame original)

  it "renders a reviewed seven-figure page with one camera and scale" $ do
    svg <- right (helmetSvg (helmetFile states))
    goldenText "test/golden/checked-helmet.svg" svg

materialError :: Surface V2 -> Double
materialError sheet = maximum (0 : errors)
  where
    points = zip (map VertexId [0 ..]) (surfaceSamples sheet)
    pairs = nub [(a, b) | ring <- facesVertices (surfaceFrame sheet), a <- ring, b <- ring, a < b]
    errors = [abs (norm (position p ^-^ position q) / norm (sampleMaterial p ^-^ sampleMaterial q) - 1) | (a, b) <- pairs, Just p <- [lookup a points], Just q <- [lookup b points]]

unit :: V3 -> V3
unit v = (1 / norm v) *^ v

name :: FaceId -> T.Text
name = T.pack . show . unFaceId

require :: String -> Maybe a -> IO a
require label = maybe (fail ("missing " ++ label)) pure

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
