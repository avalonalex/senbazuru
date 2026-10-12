-- | The helmet base, run as a sequence: the second of the two migrations
-- PRDs\/09 §9 plans. The run was shown equal to the study's hand-written
-- recipe for it (#529): every move's crease angles exactly, its layer orders,
-- every point of paper within 1e-12, and the drawn page byte for byte. The
-- recipe is gone (#534), and what it checked is checked here on the run's own
-- turns. @test/golden/checked-helmet.svg@, drawn from the run, is the guard
-- the comparison was.
--
-- It tests what the blintz cannot. After the diagonal fold, two different
-- creases of the sheet lie on one line, one on each layer, so a corner fold's
-- line names a hinge of two edges, and the faces it holds still beside them
-- face opposite ways: one turn writes opposite angles on them. The run finds
-- both creases from the one line.
--
-- A turn starts from the paper the run held then. A record keeps that paper's
-- surface, not the fold it came from, so the fold is made again: the sheet's
-- working pattern with the faces, angles and layer orders of the record's
-- surface before the turn ('startOf'). It is the one fold the recipe started
-- each turn from, since the run numbers its faces as the recipe did.
--
-- The run is of @helmet.foldseq@, the file the study's gallery runs, so the
-- two cannot run different sequences. Built once, by 'runIO' at the top.
module Senbazuru.Sequence.HelmetRunSpec (spec) where

import Control.Monad (forM_, void)
import Data.Aeson (eitherDecode, encode)
import Data.IntMap.Strict qualified as IM
import Data.List (nub, sort)
import Data.Map.Strict qualified as M
import Data.Maybe (listToMaybe)
import Data.Text qualified as T
import HelmetGallery (helmetGallery)
import Senbazuru.Fold.Load (loadFoldFile, readSequenceText)
import Senbazuru.Fold.Query (Face (..), frameFaces, frameVertices, ringEdges)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Rigid (applyRigid, inverse)
import Senbazuru.Geometry.V3 (V3 (..), cross, polygonNormal)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Flap
import Senbazuru.Origami.Folding
import Senbazuru.Origami.HingeSweep (defaultSweepSettings)
import Senbazuru.Origami.Surface
import Senbazuru.Sequence.Check (checkSequence)
import Senbazuru.Sequence.Elaborate (elaborate)
import Senbazuru.Sequence.Parse (parseSequence)
import Senbazuru.Sequence.Record
import Senbazuru.Sequence.Run (defaultRunSettings, runSequence, sheetState, workingPattern)
import SequenceGallery (pageFile, pageStates, pageSvg, turnOf)
import Test.Golden (goldenText)
import Test.Hspec

spec :: Spec
spec = describe "the helmet base, run as a sequence" $ do
  file <- runIO (loadFoldFile "examples/helmet-base.fold" >>= right)
  source <- runIO (readSequenceText "helmet.foldseq" >>= right)
  helmet <- runIO (right (parseSequence "helmet.foldseq" source))
  let runOn sheet = checkSequence helmet >>= runSequence defaultRunSettings (M.singleton "examples/helmet-base.fold" sheet) . elaborate
  helmetRun <- runIO (right (runOn file))
  let records = runRecords helmetRun
  turns <- runIO (mapM (right . turnOf) records)
  paper <- runIO (workingPattern <$> right (sheetState file))
  starts <- runIO (mapM (right . startOf paper) records)
  states <- runIO (right (pageStates helmetGallery helmetRun))

  -- From the recipe's spec, on the paper the first turn starts from: a hinge
  -- is creases, none twice, that cut the moving paper from the rest, on one
  -- line, with the moving face beside them.
  it "rejects empty, duplicate, incomplete, non-boundary and bent hinge selections" $ do
    start <- require "the first turn's start" (listToMaybe starts)
    let prepare ids side = prepareFlapAlong (map EdgeId ids) (FaceId side) 90 start
    prepare [] 5 `shouldSatisfy` (\case Left FlapEmptyHinge -> True; _ -> False)
    prepare [8, 8] 5 `shouldSatisfy` (\case Left (FlapDuplicateCrease (EdgeId 8)) -> True; _ -> False)
    prepare [8] 5 `shouldSatisfy` (\case Left FlapCoupled {} -> True; _ -> False)
    prepare [8, 9, 10, 12] 5 `shouldSatisfy` (\case Left FlapNotBoundary {} -> True; _ -> False)
    prepare [8, 10] 1 `shouldSatisfy` (\case Left (FlapUnalignedCrease (EdgeId 10)) -> True; _ -> False)
    prepare [8, 99] 5 `shouldSatisfy` (\case Left (FlapMissingCrease (EdgeId 99)) -> True; _ -> False)
    prepare [8, 0] 5 `shouldSatisfy` (\case Left (FlapNotHinge (EdgeId 0)) -> True; _ -> False)
    prepare [8, 9] 0 `shouldSatisfy` (\case Left FlapWrongSide {} -> True; _ -> False)

  -- From the recipe's spec: the diagonal fold laid three pairs of faces on
  -- one another, and with their orders taken away, nothing says they may
  -- touch, so they collide at once. Turns red if the turn were refused for
  -- any other reason, which would never reach the contact check.
  it "does not infer permission for stacked contact from coincident positions" $ do
    original <- require "the first corner's start" (listToMaybe (drop 1 starts))
    start <- right (foldFrameWith (foldedPattern original) {edgesFoldAngle = edgesFoldAngle (foldedFrame original), faceOrders = []})
    case prepareFlapAlong [EdgeId 10, EdgeId 12] (FaceId 1) 180 start >>= checkFlap defaultSweepSettings of
      Left (FlapCollision 0 pairs) -> pairs `shouldMatchList` [(FaceId 0, FaceId 4), (FaceId 1, FaceId 5), (FaceId 2, FaceId 3)]
      other -> expectationFailure ("expected the stacked faces to collide at the start, got " <> show (void other))

  -- From the recipe's spec, against the run's own first corner turn.
  it "uses the first segment's angle convention, independently of stored endpoint direction" $ do
    (original, corner) <- require "the first corner's turn" (listToMaybe (drop 1 (zip starts turns)))
    start <- right (foldFrameWith (foldedPattern original) {edgesFoldAngle = edgesFoldAngle (foldedFrame original), faceOrders = faceOrders (foldedFrame original), edgesVertices = map (\(a, b) -> (b, a)) (edgesVertices (foldedPattern original))})
    -- Segment 12 is on the upside-down layer: choosing it first reverses
    -- the sign of the supplied travel, but not the physical motion.
    motion <- right (prepareFlapAlong [EdgeId 12, EdgeId 10] (FaceId 5) (-180) start >>= checkFlap defaultSweepSettings)
    forM_ [0, 0.25, 0.5, 0.75, 1] $ \t -> do
      originalPose <- right (flapAt corner t)
      reversedPose <- right (flapAt motion t)
      edgesFoldAngle (surfaceFrame reversedPose) `shouldBe` edgesFoldAngle (surfaceFrame originalPose)
      zipWith (\a b -> norm (position a ^-^ position b)) (surfaceSamples originalPose) (surfaceSamples reversedPose) `shouldSatisfy` all (< 1e-12)

  -- From the recipe's spec, now through the runner: the whole run on the
  -- sheet scaled down and up. The source names paper in sheet lengths, so at
  -- any size it turns the same faces about the same creases to the same
  -- angles and orders, and lays the paper where the unscaled run does, times
  -- the scale. Turns red if a scaled run resolved some name to other paper.
  forM_ [1e-5, 1e5] $ \scale ->
    it ("folds the same route on the sheet scaled by " ++ show scale) $ do
      let original = keyFrame file
      scaled <- runRecords <$> right (runOn file {keyFrame = original {verticesCoords = map (map (* scale)) (verticesCoords original)}})
      route <- mapM (right . turnOf) scaled
      map flapMovingFaces route `shouldBe` map flapMovingFaces turns
      map (concatMap snd . recordHinge) scaled `shouldBe` map (concatMap snd . recordHinge) records
      map (snd . recordAngles) scaled `shouldBe` map (snd . recordAngles) records
      map (faceOrders . surfaceFrame . recordAfter) scaled `shouldBe` map (faceOrders . surfaceFrame . recordAfter) records
      forM_ (zip scaled records) $ \(big, small) -> do
        let ours = surfaceSamples (recordAfter big)
            theirs = surfaceSamples (recordAfter small)
        length ours `shouldBe` length theirs
        zip ours theirs `shouldSatisfy` all (\(p, q) -> norm (position p ^-^ scale *^ position q) <= 1e-12 * scale)
      forM_ route $ \turn -> forM_ [0, 0.37, 0.5, 0.83, 1] $ \t -> do
        surface <- right (flapAt turn t)
        length (surfaceSamples surface) `shouldBe` 9
        materialError surface `shouldSatisfy` (< 1e-12)

  -- From the recipe's spec: a sheet with every face wound backwards. The
  -- runner winds each face anticlockwise as it reads the sheet, so the
  -- backwards sheet is the same state as the forwards one, and the run, which
  -- starts from that state, is the same run. FlapSpec and FoldingSpec keep
  -- the library's own re-winding. Turns red if the runner kept a face wound
  -- as the file wrote it.
  it "reads a sheet wound backwards as the same sheet wound forwards, at any scale" $
    forM_ [1e-5, 1, 1e5] $ \scale -> do
      let original = keyFrame file
          sized = original {verticesCoords = map (map (* scale)) (verticesCoords original)}
      sheetState file {keyFrame = sized {facesVertices = map reverse (facesVertices sized)}} `shouldBe` sheetState file {keyFrame = sized}

  -- From the recipe's spec: the diagonal, then each corner of the doubled
  -- triangle, a corner turn writing opposite angles on the creases of the
  -- two layers. The angles and orders each move ends at were the recipe's
  -- exactly (#529): the first move ends with three orders, and each later
  -- move with the last move's and four more. Every turn is a checked turn,
  -- which the library makes only once its sweep is clear, so three records
  -- are three clear sweeps.
  it "completes the diagonal and both doubled corners with opposite signs on upside-down layers" $ do
    length records `shouldBe` 3
    length states `shouldBe` 7
    map flapMovingFaces turns `shouldBe` map (map FaceId) [[3, 4, 5], [1, 5], [2, 3]]
    map (snd . recordAngles) records
      `shouldBe` map (replicate 8 0 ++) [[180, 180, 0, 0, 0, 0], [180, 180, 180, 0, -180, 0], [180, 180, 180, -180, -180, 180]]
    let orders = [FaceOrder (FaceId f) (FaceId g) s | (f, g, s) <- [(4, 0, Above), (5, 1, Above), (3, 2, Above), (1, 0, Above), (5, 0, Above), (1, 4, Below), (5, 4, Below), (2, 0, Above), (3, 0, Above), (2, 4, Below), (3, 4, Below)]]
    forM_ (zip records [3, 7, 11]) $ \(record, n) ->
      faceOrders (surfaceFrame (recordAfter record)) `shouldMatchList` take n orders

  -- From the recipe's spec, on the run's turns: sampled through each turn,
  -- the paper keeps its lengths, every face's copy of a corner meets the
  -- others, the anchor's face stays put, each crease's measured angle is the
  -- angle asked for, and every contact holds.
  forM_ (zip3 [1 :: Int ..] turns starts) $ \(i, turn, start) ->
    it ("preserves lengths, shared corners, signed crease angles and contact throughout move " ++ show i) $ do
      material <- right (frameVertices (foldedPattern start))
      let materialPoints = zip (map VertexId [0 ..]) material
          originalTopology = facesVertices (foldedPattern start)
      forM_ [0, 0.1 .. 1] $ \t -> do
        sheet <- right (flapAt turn t)
        let fr = surfaceFrame sheet
        facesVertices fr `shouldBe` originalTopology
        length (surfaceSamples sheet) `shouldBe` 9
        materialError sheet `shouldSatisfy` (< 1e-12)
        points <- right (frameVertices fr)
        let placed = zip (map VertexId [0 ..]) points
        -- Independently place each face's copy of each vertex. All copies
        -- must meet at the one position exported for that material id.
        folded <- right (foldFrameWith (foldedPattern start) {edgesFoldAngle = edgesFoldAngle fr, faceOrders = faceOrders fr})
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
              (fixed, moving) <- case incident of
                [f, g] -> pure (f, g)
                _ -> fail "crease must join two faces"
              let oriented = if (a, b) `elem` ringEdges (faceVertexIds fixed) then (a, b) else (b, a)
              from <- require "hinge start" (lookup (fst oriented) placed)
              to <- require "hinge end" (lookup (snd oriented) placed)
              let axis = unit (to ^-^ from)
                  fixedNormal = unit (polygonNormal (faceCorners fixed))
                  movingNormal = unit (polygonNormal (faceCorners moving))
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

  -- From the recipe's spec: each turn starts where the one before it ended.
  it "carries exactly the accepted positions, material ids, angles and orders across each join" $
    forM_ (zip records (drop 1 turns)) $ \(previous, following) -> do
      start <- right (flapAt following 0)
      let end = recordAfter previous
      faceOrders (surfaceFrame start) `shouldMatchList` faceOrders (surfaceFrame end)
      edgesFoldAngle (surfaceFrame start) `shouldBe` edgesFoldAngle (surfaceFrame end)
      map sampleMaterial (surfaceSamples start) `shouldBe` map sampleMaterial (surfaceSamples end)
      zipWith (\a b -> norm (position a ^-^ position b)) (surfaceSamples start) (surfaceSamples end) `shouldSatisfy` all (< 1e-12)

  -- From the recipe's spec: after the three turns the paper is the fixture's
  -- own folded helmet base, its four corners meeting at the tip. The fixture
  -- numbers the south-east square 1, so the reference holds face 1 still,
  -- where the run, which puts the anchor's face first, calls it face 0.
  it "matches the existing base and independently places all four corners at the fixed tip" $ do
    completed <- require "completed base" (recordAfter <$> listToMaybe (drop 2 records))
    reference <- right (foldFrameWith (keyFrame file))
    centreTransform <- require "reference central transform" (IM.lookup 1 (foldedPlacements reference))
    expected <- map (applyRigid (inverse centreTransform)) <$> right (frameVertices (foldedFrame reference))
    actual <- right (frameVertices (surfaceFrame completed))
    length actual `shouldBe` length expected
    zipWith (\a b -> norm (a ^-^ b)) actual expected `shouldSatisfy` all (< 1e-12)
    let landmarks = replicate 4 (V3 1 0 0) ++ [V3 0.5 0 0, V3 0.5 0.5 0, V3 1 0.5 0, V3 0.5 0 0, V3 1 0.5 0]
    zipWith (\a b -> norm (a ^-^ b)) actual landmarks `shouldSatisfy` all (< 1e-12)
    length (nub (map sampleMaterial (take 4 (surfaceSamples completed)))) `shouldBe` 4

  -- From the recipe's spec, on the paper the first corner left: the corner
  -- turned back the way it came reopens; turned on the other way it reaches
  -- the same flat end through the body, which the library refuses.
  it "reopens a doubled corner on its accepted side and refuses the identical endpoint reached through the body" $ do
    (initial, record) <- require "the first corner" (listToMaybe (drop 1 (zip starts records)))
    let accepted = surfaceFrame (recordAfter record)
    start <- right (foldFrameWith (foldedPattern initial) {edgesFoldAngle = edgesFoldAngle accepted, faceOrders = faceOrders accepted})
    motion <- right (prepareFlapAlong [EdgeId 10, EdgeId 12] (FaceId 1) (-180) start >>= checkFlap defaultSweepSettings)
    end <- right (flapAt motion 1)
    edgesFoldAngle (surfaceFrame end) `shouldBe` replicate 8 0 ++ [180, 180, 0, 0, 0, 0]
    wrong <- right (prepareFlapAlong [EdgeId 10, EdgeId 12] (FaceId 1) 180 start)
    case checkFlap defaultSweepSettings wrong of
      Left FlapEndpointOrder {} -> pure ()
      other -> expectationFailure (show other)

  -- Each corner fold's line, the line halfway between the corner and the
  -- tip, lies along two creases of the sheet, one on each layer: edges 10
  -- and 12 for the first, 11 and 13 for the second. On the sheet they are
  -- perpendicular, meeting at its centre, so each is a stretch of its own.
  -- Turns red if stretches were joined wherever two creases meet, which made
  -- one stretch along edge 10 claim edge 12 too.
  it "turns each corner about a hinge of two creases, one on each layer" $ do
    map (sort . concatMap snd . recordHinge) records `shouldBe` [[EdgeId 8, EdgeId 9], [EdgeId 10, EdgeId 12], [EdgeId 11, EdgeId 13]]
    let stretches record = [(sort [xy a, xy b], edges) | (MaterialSegment (MaterialPoint a) (MaterialPoint b), edges) <- recordHinge record]
    case drop 1 records of
      [first', second'] -> do
        stretches first' `shouldMatchList` [([(0.5, 0), (0.5, 0.5)], [EdgeId 10]), ([(0, 0.5), (0.5, 0.5)], [EdgeId 12])]
        stretches second' `shouldMatchList` [([(0.5, 0.5), (1, 0.5)], [EdgeId 13]), ([(0.5, 0.5), (0.5, 1)], [EdgeId 11])]
      other -> expectationFailure ("expected two corner folds, got " <> show (length other))

  -- From the recipe's spec: the page's states survive a trip through FOLD
  -- with their material coordinates and orders.
  it "round-trips the illustrated states with their material coordinates and orders" $ do
    let page = pageFile helmetGallery states
    eitherDecode (encode page) `shouldBe` Right page
    forM_ (zip (otherFrames page) states) $ \(fr, (_, original)) -> do
      reloaded <- right (surfaceFromFrame fr)
      map sampleMaterial (surfaceSamples reloaded) `shouldBe` map (Just . sampleMaterial) (surfaceSamples original)
      faceOrders (surfaceFrame reloaded) `shouldBe` faceOrders (surfaceFrame original)

  -- The page, drawn from the run's turns: the open square, each turn part-way
  -- and each record's end. Byte for byte the golden the recipe's page was,
  -- and now the guard that the run still folds the helmet the way it was
  -- shown equal to the recipe.
  it "draws the seven-figure page, checked-helmet.svg, byte for byte" $ do
    svg <- right (pageSvg helmetGallery (pageFile helmetGallery states))
    goldenText "test/golden/checked-helmet.svg" svg
  where
    xy (V2 x y) = (x, y)

-- | The fold a turn started from: the sheet's working pattern with the faces,
-- angles and layer orders of the record's surface before the turn. The faces
-- come from the record, numbered as the run numbered them, not as the sheet
-- read on its own would, whose anchor is its own default.
startOf :: Frame -> MoveRecord -> Either FoldingError Folded
startOf paper record =
  let was = surfaceFrame (recordBefore record)
   in foldFrameWith paper {facesVertices = facesVertices was, edgesFoldAngle = edgesFoldAngle was, faceOrders = faceOrders was}

-- | The largest relative change of length between any two corners of one
-- face, from the sheet to the pose: 0 for paper that does not stretch. A NaN
-- comes through. @maximum (0 : errors)@ would lose it, because 'max' keeps its
-- first argument whenever a comparison with NaN fails.
materialError :: Surface V2 -> Double
materialError sheet = foldr worse 0 errors
  where
    worse e m = if isNaN e || e > m then e else m
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
