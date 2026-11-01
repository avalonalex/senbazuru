-- |
-- Tests for what of a flat-folded model can be seen.
--
-- The assertions are areas and counts rather than coordinates, because that is
-- what can be checked against paper. Fold a square into quarters and one
-- quadrant of it is showing: a quarter of the sheet, bounded by four lines and
-- nothing else, however many layers went into it. Fold a strip in three and the
-- silhouette is the widest panel, with the narrow one peeping out beside it.
-- Both numbers come from the fixture's own coordinates, not from a previous
-- run of this code.
--
-- Two invariants are then checked on every fixture, including the ones nobody
-- could work out by hand. The visible parts must not overlap one another —
-- they are meant to tile the silhouette, and a gap or a double covering is how
-- a hidden-line algorithm goes wrong quietly. And every line drawn must be on
-- the edge of something visible, since a line floating over bare page is a
-- line the removal missed.
module Senbazuru.Origami.VisibleSpec (spec) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.List (sort, tails)
import Data.Map.Strict qualified as M
import Senbazuru.Fold.Load (decodeFoldFile, loadFoldFile, readSequenceText)
import Senbazuru.Fold.Query (Face (..), FoldError (..), frameFaces, frameVertices)
import Senbazuru.Fold.Types
  ( Assignment (..),
    FaceId (..),
    FaceOrder,
    FoldFile (..),
    Frame (..),
    VertexId (..),
    emptyFrame,
    keyFrame,
  )
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (clipConvex, cross2, signedArea)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Flat (FlatError (..), Sheet (..), flatSheet)
import Senbazuru.Origami.Folding (foldFrame)
import Senbazuru.Origami.Layers (paintOrder)
import Senbazuru.Origami.Stacking (solveStacking)
import Senbazuru.Origami.Visible
import Senbazuru.Sequence.Check (checkSequence)
import Senbazuru.Sequence.Elaborate (elaborate)
import Senbazuru.Sequence.Parse (parseSequence)
import Senbazuru.Sequence.Run (defaultRunSettings, runSequence)
import Senbazuru.Sequence.Write (noFileHeader, writeSequence)
import Test.Hspec

-- | The key frame of a fixture, as the file gives it.
fixture :: String -> IO Frame
fixture name = do
  bytes <- BS.readFile ("test/fixtures/" <> name <> ".fold")
  case decodeFoldFile bytes of
    Left err -> fail ("decode failed: " <> err)
    Right f -> pure (keyFrame f)

-- | A crease-pattern fixture, folded along its own angles.
foldedFixture :: String -> IO Frame
foldedFixture name = do
  fr <- fixture name
  case foldFrame fr of
    Left err -> fail ("fold failed: " <> show err)
    Right folded -> pure folded

-- | The layer order senbazuru works out for a folded frame.
orders :: Frame -> IO [FaceOrder]
orders fr = case solveStacking fr of
  Left err -> fail ("stacking failed: " <> show err)
  Right os -> pure os

-- | A folded fixture, its layers solved, seen from the given side.
seen :: Bool -> String -> IO VisibleForm
seen fromAbove name = do
  folded <- foldedFixture name
  os <- orders folded
  case visibleForm fromAbove folded os of
    Left err -> fail ("visible failed: " <> show err)
    Right v -> pure v

flatten :: V3 -> V2
flatten (V3 x y _) = V2 x y

-- | Every visible piece of paper, as a ring in the plane.
pieces :: VisibleForm -> [[V2]]
pieces v = [map flatten piece | r <- formRegions v, piece <- regionPieces r]

-- | How much paper is showing.
visibleArea :: VisibleForm -> Double
visibleArea = sum . map (abs . signedArea) . pieces

-- | The area of one region.
areaOf :: Region -> Double
areaOf r = sum [abs (signedArea (map flatten piece)) | piece <- regionPieces r]

-- | Close enough, for numbers that came out of a folding simulation.
near :: Double -> Double -> Bool
near a b = abs (a - b) < 1e-9

-- | How far outside a convex ring a point is, and zero if it is inside or on
-- the boundary.
--
-- Zero-length edges are skipped: a ring can carry one where a clip passed
-- exactly through a corner, and the direction it would give is noise.
howFarOutside :: [V2] -> V2 -> Double
howFarOutside ring p =
  maximum
    ( 0
        : [ negate (cross2 (b ^-^ a) (p ^-^ a)) / norm (b ^-^ a)
            | (a, b) <- zip ring (drop 1 ring <> take 1 ring),
              norm (b ^-^ a) > 1e-12
          ]
    )

-- | Every flat-folded fixture, and both sides of each.
everyFlatFixture :: [(String, Bool)]
everyFlatFixture =
  [ (name, side)
    | name <- ["quarter-fold", "letter-fold", "thirds-pinwheel", "grid-2x2-d1", "kabuto", "crane"],
      side <- [True, False]
  ]

sideName :: Bool -> String
sideName fromAbove = if fromAbove then "from above" else "from below"

-- | A folded fixture with the layer order senbazuru works out written into it,
-- and the side it is to be seen from.
framed :: Bool -> String -> IO (Bool, Frame)
framed side name = do
  folded <- foldedFixture name
  os <- orders folded
  pure (side, folded {faceOrders = os})

-- | The helmet base's last state, as the run of @helmet.foldseq@ writes it:
-- @file_frames[3]@, its faces ordered by the run.
helmetLast :: IO Frame
helmetLast = do
  sheet <- loadFoldFile "examples/helmet-base.fold" >>= right
  source <- readSequenceText "helmet.foldseq" >>= right
  run <- right (parseSequence "helmet.foldseq" source >>= checkSequence >>= runSequence defaultRunSettings (M.singleton "examples/helmet-base.fold" sheet) . elaborate)
  file <- right (writeSequence noFileHeader run)
  case drop 3 (otherFrames file) of
    st : _ -> pure st
    [] -> fail "the helmet run wrote fewer than four states"

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure

-- | Each vertex of a frame where it lies, by id.
positionsOf :: Frame -> IO (M.Map VertexId V2)
positionsOf fr = do
  vs <- right (frameVertices fr)
  pure (M.fromList (zip (map VertexId [0 ..]) (map flatten vs)))

-- | The point a fraction of the way along a span's edge.
pointOf :: M.Map VertexId V2 -> EdgeSpan -> Double -> V2
pointOf at sp t = p ^+^ (t *^ (q ^-^ p))
  where
    p = M.findWithDefault (V2 (0 / 0) 0) (spanFrom sp) at
    q = M.findWithDefault (V2 (0 / 0) 0) (spanTo sp) at

-- | Whether a fraction lies well inside its edge, neither end.
inside :: Double -> Bool
inside t = t > 0.01 && t < 0.99

-- | Whether two vertices are neighbours around a face's ring, either way.
isEdgeOf :: Frame -> FaceId -> (VertexId, VertexId) -> Bool
isEdgeOf fr (FaceId f) (u, v) = case drop f (facesVertices fr) of
  ring : _ -> any (\(a, b) -> (a, b) == (u, v) || (a, b) == (v, u)) (zip ring (drop 1 ring <> take 1 ring))
  [] -> False

-- | The assignment the frame gives the edge between two vertices.
assignmentOf :: Frame -> (VertexId, VertexId) -> Maybe Assignment
assignmentOf fr (u, v) = case [a | ((a', b'), a) <- zip (edgesVertices fr) (edgesAssignment fr), (a', b') == (u, v) || (a', b') == (v, u)] of
  a : _ -> Just a
  [] -> Nothing

-- | A face's corners where they lie, in the plane.
faceRing :: Frame -> FaceId -> IO [V2]
faceRing fr f = do
  faces <- right (frameFaces fr)
  case [map flatten (faceCorners face) | face <- faces, faceId face == f] of
    ring : _ -> pure ring
    [] -> fail ("no face " <> show f)

-- | How far inside a convex ring a point is: the least distance to any of
-- its edges' lines, negative outside, whichever way the ring winds.
howFarInside :: [V2] -> V2 -> Double
howFarInside ring p = minimum [turn * cross2 (b ^-^ a) (p ^-^ a) / norm (b ^-^ a) | (a, b) <- zip ring (drop 1 ring <> take 1 ring), norm (b ^-^ a) > 1e-12]
  where
    turn = if signedArea ring > 0 then 1 else -1

spec :: Spec
spec = do
  describe "coincident layers" $ do
    it "shows the quarter fold as one region, a quarter of the sheet" $ do
      -- All four faces land on the same quadrant, so three of them are hidden
      -- completely and the fourth is showing whole. The unit square's quadrant
      -- is 0.25, and no arithmetic in the fixture says so -- it is what folding
      -- a unit square twice does.
      v <- seen True "quarter-fold"
      map areaOf (formRegions v) `shouldSatisfy` all (near 0.25)
      length (formRegions v) `shouldBe` 1
      length (pieces v) `shouldBe` 1

    it "draws only the outline of the quarter fold" $ do
      -- Eight border edges and four creases went in. Two sides of the quadrant
      -- are the edge of the paper, with two coincident border edges each; two
      -- are folds. Nothing is left over to draw inside.
      v <- seen True "quarter-fold"
      sort (map visibleAssignment (formEdges v)) `shouldBe` [Border, Border, Mountain, Valley]

  describe "a layer covering another" $ do
    it "shows the long panel of the letter fold covering the short ones" $ do
      -- The strip is 1 wide with panels of 0.3, 0.2 and 0.5, folded to a
      -- silhouette 0.6 wide and 1 tall. The long panel takes 0.5 of that and
      -- the first panel's uncovered strip the remaining 0.1; the middle panel
      -- is buried.
      v <- seen True "letter-fold"
      sort (map areaOf (formRegions v)) `shouldSatisfy` \as ->
        length as == 2 && and (zipWith near as [0.1, 0.5])
      visibleArea v `shouldSatisfy` near 0.6

    it "hides the crease the long panel lies over" $ do
      -- Both creases of the letter fold end up inside the silhouette, and only
      -- one of them is still on the surface. Drawing the other is what a
      -- wireframe does and what this is for.
      v <- seen True "letter-fold"
      filter (`elem` [Mountain, Valley]) (map visibleAssignment (formEdges v))
        `shouldBe` [Mountain]

  describe "a twist" $ do
    forM_ ["thirds-pinwheel", "grid-2x2-d1"] $ \name ->
      it ("draws " <> name <> ", whose layers stack in a circle") $ do
        -- The flaps of a twist lie A over B over C over A, which is a valid
        -- stacking with no point under all three of them at once. There is no
        -- order to paint whole faces in, and 'paintOrder' refuses to invent
        -- one; there is still a picture, and this is it.
        folded <- foldedFixture name
        os <- orders folded
        faces <- either (fail . show) pure (frameFaces folded)
        paintOrder (V3 0 0 1) faces os `shouldSatisfy` \case
          Left (ImpossibleStacking _) -> True
          _ -> False
        v <- seen True name
        formRegions v `shouldSatisfy` (not . null)
        formEdges v `shouldSatisfy` (not . null)

  describe "the two sides of the paper" $ do
    it "turns the letter fold over to show the back of both panels" $ do
      -- Neither panel was flipped an odd number of times, so from above both
      -- show the side the crease pattern was drawn on, and from below both
      -- show the other one.
      above <- seen True "letter-fold"
      below <- seen False "letter-fold"
      map regionTopSide (formRegions above) `shouldBe` [True, True]
      map regionTopSide (formRegions below) `shouldBe` [False, False]

    it "sees the same silhouette from either side" $ do
      -- A different set of faces is on top, and the outline they add up to is
      -- the same paper: a model has one shadow.
      forM_ ["quarter-fold", "letter-fold", "thirds-pinwheel", "kabuto", "crane"] $ \name -> do
        above <- seen True name
        below <- seen False name
        visibleArea above `shouldSatisfy` near (visibleArea below)

  describe "every fixture" $ do
    forM_ everyFlatFixture $ \(name, side) -> do
      it ("tiles " <> name <> " " <> sideName side <> " without overlaps") $ do
        v <- seen side name
        let worst =
              maximum
                (0 : [abs (signedArea (clipConvex p q)) | (p : rest) <- tails (pieces v), q <- rest])
        worst `shouldSatisfy` (< 1e-9)

      it ("draws no line off the paper of " <> name <> " " <> sideName side) $ do
        -- Every stretch that survives is the boundary between two different
        -- things, so its middle has to lie on the edge of a visible piece.
        v <- seen side name
        let middles = [0.5 *^ (flatten (visibleFrom e) ^+^ flatten (visibleTo e)) | e <- formEdges v]
            -- Seeded, so a fixture that produced no paper at all fails this
            -- assertion rather than throwing from inside `minimum`.
            stray m = minimum (1 / 0 : map (`howFarOutside` m) (pieces v)) > 1e-9
        pieces v `shouldSatisfy` (not . null)
        filter stray middles `shouldBe` []

      it ("stops no line in the middle of the paper of " <> name <> " " <> sideName side) $ do
        -- A line ends where the paper on its two sides stops differing, and
        -- what makes them stop differing is another edge -- so every end of
        -- every stretch has to be met by a second one, at its end or somewhere
        -- along it. This caught a real bug and is the reason it is here: a face
        -- whose edge lay exactly along a stretch was being dropped from the
        -- reckoning altogether, so the two sides agreed because neither could
        -- see it, and creases stopped dead in the middle of the crane.
        v <- seen side name
        let ends = concat [[flatten (visibleFrom e), flatten (visibleTo e)] | e <- formEdges v]
            met p = length (filter (samePoint p) ends) >= 2 || any (runsThrough p) (formEdges v)
            samePoint p q = norm (q ^-^ p) < 1e-9
            runsThrough p e =
              let (a, b) = (flatten (visibleFrom e), flatten (visibleTo e))
               in not (samePoint p a)
                    && not (samePoint p b)
                    && abs (cross2 (b ^-^ a) (p ^-^ a)) < 1e-9 * norm (b ^-^ a)
                    && dot (p ^-^ a) (b ^-^ a) > 0
                    && dot (p ^-^ b) (a ^-^ b) > 0
        filter (not . met) ends `shouldBe` []

  describe "a frame with no faces" $ do
    it "is every crease and no paper, not an empty page" $ do
      -- Files that record no faces_vertices are common, and a folded form drawn
      -- from one was a wireframe long before any of this existed. Nothing
      -- covers its creases, so nothing hides them.
      let square =
            emptyFrame
              { verticesCoords = [[0, 0], [1, 0], [1, 1], [0, 1]],
                edgesVertices =
                  [ (VertexId 0, VertexId 1),
                    (VertexId 1, VertexId 2),
                    (VertexId 2, VertexId 3),
                    (VertexId 3, VertexId 0)
                  ],
                edgesAssignment = replicate 4 Border
              }
      case visibleForm True square [] of
        Left err -> expectationFailure ("declined: " <> show err)
        Right v -> do
          formRegions v `shouldBe` []
          length (formEdges v) `shouldBe` 4
          -- No faces, so no stretch has a sheet to name, and none names an
          -- edge either: the first of the cases with no edge. Red if an edge
          -- were named where no sheet is.
          map sheetEdgeFace (formSheetEdges v) `shouldBe` replicate 4 Nothing
          map sheetEdgeSpan (formSheetEdges v) `shouldBe` replicate 4 Nothing

  -- R-05-52: each stretch of formSheetEdges names the face edge it lies
  -- along, so a drawing that moves the sheets apart can move a point partway
  -- along a stretch with that edge, by fractions rather than by matching
  -- coordinates afterwards.
  describe "the edge each stretch lies along" $ beforeAll helmetLast $ do
    -- Read the named edge at the two fractions and get the stretch's two
    -- ends, within the folded form's hair, on every flat fixture from both
    -- sides and on the helmet base's last state. Every named sheet has an
    -- edge there, since these frames order every overlapping pair, and the
    -- edge named is that sheet's own. Red if the code named the right face's
    -- wrong edge, snapped a fraction to the nearer vertex (the letter fold
    -- below makes sure some stretch ends inside its edge), swapped the two
    -- fractions, named another face's edge along the same line, or listed an
    -- edge's two vertices against the order edges_vertices gives them.
    it "names an edge of the sheet named, whose fractions give the stretch's ends" $ \helmet -> do
      fixtures <- mapM (\(name, side) -> (,) (name <> " " <> sideName side) <$> framed side name) everyFlatFixture
      let cases = fixtures <> [("the helmet base " <> sideName side, (side, helmet)) | side <- [True, False]]
      forM_ cases $ \(name, (side, fr)) -> do
        v <- right (visibleForm side fr (faceOrders fr))
        hair <- sheetHair <$> right (flatSheet fr)
        at <- positionsOf fr
        forM_ (formSheetEdges v) $ \e -> case (sheetEdgeFace e, sheetEdgeSpan e) of
          (Nothing, _) -> pure ()
          (Just _, Nothing) -> expectationFailure (name <> ": a named sheet with no edge along " <> show e)
          (Just f, Just sp) -> do
            (name, isEdgeOf fr f (spanFrom sp, spanTo sp)) `shouldBe` (name, True)
            (name, (spanFrom sp, spanTo sp) `elem` edgesVertices fr) `shouldBe` (name, True)
            let line = sheetEdgeLine e
            (name, flatten (visibleFrom line), pointOf at sp (spanStart sp)) `shouldSatisfy` (\(_, p, q) -> norm (q ^-^ p) <= hair)
            (name, flatten (visibleTo line), pointOf at sp (spanEnd sp)) `shouldSatisfy` (\(_, p, q) -> norm (q ^-^ p) <= hair)

    -- The letter fold's unequal panels leave a stretch that stops partway
    -- along its edge, so a fraction there is neither 0 nor 1. Without one, a
    -- fraction snapped to the nearer vertex would pass the test above.
    it "has a stretch on the letter fold that ends inside its edge" $ \_ -> do
      (_, fr) <- framed True "letter-fold"
      v <- right (visibleForm True fr (faceOrders fr))
      [sp | e <- formSheetEdges v, Just sp <- [sheetEdgeSpan e], inside (spanStart sp) || inside (spanEnd sp)]
        `shouldSatisfy` (not . null)

    -- Where a top face's fold lies along the border of a layer buried under
    -- it, the stretch names the fold, its own face's edge, though it is drawn
    -- as the border, the stronger line. The crane has such stretches from
    -- above. Red if the code named whichever crease along the line came
    -- first, or the strongest, which is the buried border.
    it "names the fold, not the buried border, where a fold lies along one" $ \_ -> do
      (_, fr) <- framed True "crane"
      v <- right (visibleForm True fr (faceOrders fr))
      let foldsDrawnAsBorder =
            [ sp
              | e <- formSheetEdges v,
                visibleAssignment (sheetEdgeLine e) == Border,
                Just sp <- [sheetEdgeSpan e],
                assignmentOf fr (spanFrom sp, spanTo sp) `elem` [Just Mountain, Just Valley]
            ]
      length foldsDrawnAsBorder `shouldSatisfy` (> 0)

    -- A face with two edges along one line, a straight corner, which tracing
    -- can leave where one crease ends on another, gives a stretch for each
    -- edge, though the ordinary drawing joins them into one line. No fixture
    -- has one, so this frame is built for it: a square whose bottom side is
    -- two edges, through a vertex at its middle. Red if stretches were joined
    -- whatever edge they name, which would hand a fanned drawing one stretch
    -- moving with one edge for the length of two.
    it "gives each of two edges along one line a stretch of its own" $ \_ -> do
      let corner =
            emptyFrame
              { verticesCoords = [[0, 0], [0.5, 0], [1, 0], [1, 1], [0, 1]],
                facesVertices = [map VertexId [0, 1, 2, 3, 4]],
                edgesVertices = [(VertexId a, VertexId b) | (a, b) <- [(0, 1), (1, 2), (2, 3), (3, 4), (4, 0)]],
                edgesAssignment = replicate 5 Border
              }
      v <- right (visibleForm True corner [])
      length (formEdges v) `shouldBe` 4
      [(spanFrom sp, spanTo sp, spanStart sp, spanEnd sp) | e <- formSheetEdges v, Just sp <- [sheetEdgeSpan e], spanFrom sp `elem` [VertexId 0, VertexId 1], spanTo sp `elem` [VertexId 1, VertexId 2]]
        `shouldBe` [(VertexId 0, VertexId 1, 0, 1), (VertexId 1, VertexId 2, 0, 1)]

    -- With the letter fold's orders dropped, the face found nearest along one
    -- stretch is a face whose middle that stretch crosses, so it has no edge
    -- there, and the stretch names the sheet and no edge. Red if an edge of
    -- that face were named anyway.
    it "names no edge where the sheet named has none along the stretch, with orders missing" $ \_ -> do
      (_, fr) <- framed True "letter-fold"
      v <- right (visibleForm True fr [])
      let edgeless = [e | e <- formSheetEdges v, Just _ <- [sheetEdgeFace e], Nothing <- [sheetEdgeSpan e]]
      length edgeless `shouldBe` 1
      forM_ edgeless $ \e -> case sheetEdgeFace e of
        Just f -> do
          ring <- faceRing fr f
          let line = sheetEdgeLine e
              mid = 0.5 *^ (flatten (visibleFrom line) ^+^ flatten (visibleTo line))
          -- Well inside the face: the stretch crosses its middle.
          howFarInside ring mid `shouldSatisfy` (> 1e-6)
        Nothing -> pure ()

  describe "what it declines" $ do
    it "declines a model with paper still in the air" $ do
      -- The rigidly folded square twist stands up out of the plane, so there
      -- is no one plane to cut into regions and no plane geometry to do it
      -- with. Declined rather than refused: the caller draws it as it always
      -- has, through "Senbazuru.Origami.Layers".
      fr <- fixture "squaretwist"
      visibleForm True fr [] `shouldSatisfy` \case
        Left (PaperInTheAir dz) -> dz > 0
        _ -> False
