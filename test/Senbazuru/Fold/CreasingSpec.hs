-- |
-- Tests for drawing a crease on a sheet.
--
-- Adding the segment is the easy half and barely appears here. What these
-- assert is the other half: which vertex the crease joined rather than
-- duplicated, what got cut on the way, and which of the file's own claims
-- stopped being true the moment the line was drawn.
--
-- The refusals matter as much as the successes, and the pair worth reading
-- together is an end off the paper and an end in the middle of it: both are
-- refused, for the same stated reason, and getting that reason right is what
-- the module header of "Senbazuru.Fold.Creasing" is about.
module Senbazuru.Fold.CreasingSpec (spec) where

import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.List (partition)
import Senbazuru.Fold.Creasing
import Senbazuru.Fold.Load (decodeFile, renderLoadError)
import Senbazuru.Fold.Query (CreaseEnd (..), FoldError (..), frameVertices, renderFoldError)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..), norm, (^-^))
import Senbazuru.Geometry.Polygon (centroid, insideRing)
import Senbazuru.Geometry.V3 (modelSpan)
import Senbazuru.Origami.Folding (Folded (..), foldFrameWith)
import Test.Hspec

-- | Load a fixture's key frame, in whatever format it is in.
fixture :: FilePath -> IO Frame
fixture name = do
  let path = "test/fixtures/" <> name
  bytes <- BS.readFile path
  case decodeFile path bytes of
    Left err -> fail (show (renderLoadError err))
    Right f -> pure (keyFrame f)

-- | A crease pattern with the given creases and nothing else recorded.
sheet :: [[Double]] -> [(Int, Int)] -> Frame
sheet points es =
  emptyFrame
    { frameClasses = ["creasePattern"],
      verticesCoords = points,
      edgesVertices = [(VertexId a, VertexId b) | (a, b) <- es]
    }

-- | The unit square, as four corners and four sides.
square :: Frame
square = sheet [[0, 0], [1, 0], [1, 1], [0, 1]] [(0, 1), (1, 2), (2, 3), (3, 0)]

-- | A file in @examples\/@, its key frame.
fromExamples :: FilePath -> IO Frame
fromExamples name = do
  let path = "examples/" <> name
  bytes <- BS.readFile path
  either (fail . show . renderLoadError) (pure . keyFrame) (decodeFile path bytes)

-- | The batch PRD 05's L2 works through on @diagonal-cp.fold@: a valley from
-- (0, 1/2) to (1/2, 0), and a mountain along the other diagonal, from (0, 0)
-- to (1, 1), which crosses the valley and the file's own diagonal.
diagonalBatch :: [(V2, V2, Assignment)]
diagonalBatch = [(V2 0 0.5, V2 0.5 0, Valley), (V2 0 0, V2 1 1, Mountain)]

-- | The unit square with a valley along one diagonal, and no angles recorded:
-- folding reads its letters, and folds the valley to +180.
lettered :: Frame
lettered = (sheet [[0, 0], [1, 0], [1, 1], [0, 1]] [(0, 1), (1, 2), (2, 3), (3, 0), (0, 2)]) {edgesAssignment = [Border, Border, Border, Border, Valley]}

-- | Fold two patterns and require that every vertex of the first lands where
-- the second's vertex of that id does, within a billionth of the model's
-- size. The second pattern's faces are reordered first, so that a face lying
-- in the first's face 0 comes first: folding holds its first face still, and
-- creasing re-traces faces in edge order, so without it two folds of one
-- paper differ by a rigid motion of the whole model.
foldsAlike :: Frame -> Frame -> Expectation
foldsAlike input output = do
  foldedIn <- either (fail . show) pure (foldFrameWith input)
  let ring fr face = [V2 x y | VertexId v <- face, x : y : _ <- take 1 (drop v (verticesCoords fr))]
      paper = foldedPattern foldedIn
      first' = case facesVertices paper of
        face : _ -> ring paper face
        [] -> []
      (lying, others) = partition (insideRing 0 first' . centroid . ring output) (facesVertices output)
  -- Without a face to hold still where the input held its first, the two
  -- folds could differ by a rigid motion and the comparison would say so for
  -- the wrong reason.
  lying `shouldNotBe` []
  foldedOut <- either (fail . show) pure (foldFrameWith output {facesVertices = lying <> others})
  placedBefore <- either (fail . show) pure (frameVertices (foldedFrame foldedIn))
  placedAfter <- either (fail . show) pure (frameVertices (foldedFrame foldedOut))
  let span' = max 1 (modelSpan placedBefore)
      kept = length (verticesCoords input)
  [i | (i, p, q) <- zip3 [0 :: Int ..] (take kept placedBefore) placedAfter, norm (q ^-^ p) > 1e-9 * span'] `shouldBe` []

-- | A frame's creases as plain pairs.
creasesOf :: Frame -> [(Int, Int)]
creasesOf fr = [(a, b) | (VertexId a, VertexId b) <- edgesVertices fr]

spec :: Spec
spec = do
  describe "where a crease's ends go" $ do
    it "joins a corner the paper already has, rather than adding a second one" $ do
      -- Appending a vertex at a place the sheet already has one leaves the
      -- crease hanging off a point joined to nothing, and the face tracing
      -- refuses it -- correctly, which is why this is worth pinning: the bug
      -- shows up as a refusal about the wrong thing.
      case creaseAlong (V2 0 0) (V2 1 1) Valley square of
        Left err -> expectationFailure (show err)
        Right s -> do
          verticesCoords s `shouldBe` verticesCoords square
          creasesOf s `shouldBe` [(0, 1), (1, 2), (2, 3), (3, 0), (0, 2)]

    it "adds a vertex where an end lands in the middle of a side, and cuts it" $ do
      case creaseAlong (V2 0.5 0) (V2 0.5 1) Mountain square of
        Left err -> expectationFailure (show err)
        Right s -> do
          drop 4 (verticesCoords s) `shouldBe` [[0.5, 0], [0.5, 1]]
          -- Both sides the crease lands on are cut at it, and the new crease
          -- runs between the two new corners.
          creasesOf s
            `shouldBe` [(0, 4), (4, 1), (1, 2), (2, 5), (5, 3), (3, 0), (4, 5)]

    it "numbers the second end correctly when only the first joins a corner" $ do
      -- The off-by-one this had: numbering the ends 0 and 1 up front is wrong
      -- exactly when one lands on a corner and the other does not, which is
      -- the commonest crease there is.
      case creaseAlong (V2 0 0) (V2 1 0.5) Valley square of
        Left err -> expectationFailure (show err)
        Right s -> do
          drop 4 (verticesCoords s) `shouldBe` [[1, 0.5]]
          creasesOf s `shouldBe` [(0, 1), (1, 4), (4, 2), (2, 3), (3, 0), (0, 4)]

    -- Two corners within the tolerance of one end, a billionth of the
    -- square's diagonal, 1.414e-9: the square's own corner at the origin, and
    -- one 2.5e-9 along its south side, where an imported file's rounding might
    -- leave a second. The end lies 1.4e-9 from the first, just inside the
    -- tolerance, and 1.1e-9 from the second, and joins the second. Turns red
    -- if the first corner within the tolerance were taken, by id, rather than
    -- the nearest.
    it "joins the nearer of two corners within the tolerance, not the first" $ do
      let split = sheet [[0, 0], [1, 0], [1, 1], [0, 1], [2.5e-9, 0]] [(0, 4), (4, 1), (1, 2), (2, 3), (3, 0)]
      case creaseAlong (V2 1.4e-9 0) (V2 1 1) Valley split of
        Left err -> expectationFailure (show err)
        Right s -> do
          verticesCoords s `shouldBe` verticesCoords split
          drop 5 (creasesOf s) `shouldBe` [(4, 2)]

    -- The same choice between a corner the paper has and an end the batch
    -- added. The first crease adds a corner 1.6e-9 along the south side,
    -- beyond the tolerance from the origin; the second starts 1.0e-9 from the
    -- origin and 0.6e-9 from that new corner, and joins the new corner.
    -- Joined to the origin instead, it would pass within the tolerance of the
    -- new corner, be cut there, and lay a piece along the south side's: the
    -- batch was refused. Turns red if the paper's corners were looked at
    -- before, rather than with, the batch's own.
    it "joins an end the batch added when it is nearer than a corner the paper has" $
      case creaseAllAlong [(V2 1.6e-9 0, V2 1 1, Valley), (V2 1.0e-9 0, V2 1 0.5, Valley)] square of
        Left err -> expectationFailure (show err)
        Right s -> drop 6 (creasesOf s) `shouldBe` [(4, 2), (4, 5)]

    it "is cut wherever it crosses a crease already there" $ do
      -- The diagonal of the quarter fold passes through its centre, which is
      -- already a vertex, so the new crease arrives as two pieces.
      fr <- fixture "quarter-fold.fold"
      case creaseAlong (V2 0 0) (V2 1 1) Valley fr of
        Left err -> expectationFailure (show err)
        Right s -> do
          length (verticesCoords s) `shouldBe` 9
          length (edgesVertices s) `shouldBe` 14
          length (facesVertices s) `shouldBe` 6

  describe "what the new crease carries" $ do
    it "gives every piece of it the assignment it was drawn with" $ do
      fr <- fixture "quarter-fold.fold"
      fmap (drop 12 . edgesAssignment) (creaseAlong (V2 0 0) (V2 1 1) Valley fr)
        `shouldBe` Right [Valley, Valley]

    it "gives the new crease the angle its assignment implies" $ do
      -- Not nought. A valley with an angle of nought is not a valley -- FOLD
      -- puts a valley's angle in (0, 180] -- and foldFrame reads exactly this
      -- off the assignment when the array is absent. Writing nought made the
      -- same command mean two things depending on whether the file happened to
      -- record angles, and left the crease unfoldable on the files that did.
      fr <- fixture "quarter-fold.fold"
      fmap (drop 12 . edgesFoldAngle) (creaseAlong (V2 0 0) (V2 1 1) Valley fr)
        `shouldBe` Right [180, 180]
      fmap (drop 12 . edgesFoldAngle) (creaseAlong (V2 0 0) (V2 1 1) Mountain fr)
        `shouldBe` Right [-180, -180]
      fmap (drop 12 . edgesFoldAngle) (creaseAlong (V2 0 0) (V2 1 1) Flat fr)
        `shouldBe` Right [0, 0]

    it "leaves an angle array the file did not have absent" $
      -- There the file made no claim about any crease's angle, and folding
      -- derives them all from the assignments the same way.
      fmap edgesFoldAngle (creaseAlong (V2 0 0) (V2 1 1) Valley square)
        `shouldBe` Right []

    it "records the assignment even when the file kept no array for it" $ do
      -- The one thing the caller actually asked for. An absent
      -- edges_assignment means "nothing is known about any crease", which is
      -- what U means -- so the array it becomes says exactly what the absence
      -- said, plus the crease somebody has now decided about. It used to say
      -- nothing at all, and the valley the user asked for existed nowhere in
      -- the output.
      fmap edgesAssignment (creaseAlong (V2 0 0) (V2 1 1) Valley square)
        `shouldBe` Right [Unassigned, Unassigned, Unassigned, Unassigned, Valley]

    it "refuses an array that does not line up rather than mislabelling a crease" $ do
      -- Appending to a short array writes the new assignment onto an existing
      -- crease and leaves the new one with none. The file is one Fold.Query
      -- refuses wherever the arrays are read; this refuses it before
      -- transforming it into a still-mismatched file.
      let short = square {edgesAssignment = [Border, Border]}
      creaseAlong (V2 0 0) (V2 1 1) Valley short
        `shouldBe` Left (ArrayLengthMismatch "edges_vertices" 4 "edges_assignment" 2)

    it "puts the crease on the sheet's own plane, not on z = 0" $ do
      let raised = sheet [[0, 0, 5], [1, 0, 5], [1, 1, 5], [0, 1, 5]] [(0, 1), (1, 2), (2, 3), (3, 0)]
      fmap verticesCoords (creaseAlong (V2 0.5 0) (V2 0.5 1) Valley raised)
        `shouldBe` Right (verticesCoords raised <> [[0.5, 0, 5], [0.5, 1, 5]])

  -- PRD 05's L2: the angle new creases are drawn at, and where each request
  -- went. Its four rules, R-05-6 to R-05-9, are the four tests here, apart
  -- from R-05-6's own sentence, that creaseAllAlong is creaseAllAlongWith
  -- FlatForAssignment: it is defined so, which no test of it could turn red.
  -- The tests above, run through creaseAllAlong, are what hold its output
  -- where it was.
  describe "drawing at rest, and where each crease went" $ do
    -- 05 L2's table, until now worked by hand and in Python: the file's
    -- diagonal, edge 4, comes out as edges 6 and 7, because each edge cut
    -- before it pushes its pieces along, and nothing in the counts says the
    -- five new pieces split 2 + 3 rather than 3 + 2. Turns red if ids came
    -- from counts, or the chains were regrouped.
    it "hands back each request's pieces, in order from its first end (R-05-9)" $ do
      cp <- fromExamples "diagonal-cp.fold"
      fmap snd (creaseAllAlongWith AtRest diagonalBatch cp) `shouldBe` Right [[EdgeId 8, EdgeId 9], [EdgeId 10, EdgeId 11, EdgeId 12]]
      fmap snd (creaseAllAlongWith FlatForAssignment diagonalBatch cp) `shouldBe` Right [[EdgeId 8, EdgeId 9], [EdgeId 10, EdgeId 11, EdgeId 12]]
      fmap snd (creaseAllAlongWith AtRest [(V2 0 0, V2 1 1, Valley)] square) `shouldBe` Right [[EdgeId 4]]
      creaseAllAlongWith AtRest [] cp `shouldBe` Right (cp, [])

    -- The new pieces at 0 with their letters; the old diagonal's two pieces
    -- at its 180, the four sides' pieces at 0. Turns red if a cut old crease
    -- were zeroed, or a new one given its letter's angle.
    it "draws every new piece at 0 with its letter, and keeps the old pieces' angles (R-05-7)" $ do
      cp <- fromExamples "diagonal-cp.fold"
      case creaseAllAlongWith AtRest diagonalBatch cp of
        Left err -> expectationFailure (show err)
        Right (s, _) -> do
          edgesFoldAngle s `shouldBe` [0, 0, 0, 0, 0, 0, 180, 180, 0, 0, 0, 0, 0]
          edgesAssignment s `shouldBe` replicate 6 Border <> [Valley, Valley, Valley, Valley, Mountain, Mountain, Mountain]
      -- Drawn flat for their letters, the same requests come out at +180 and
      -- -180, as the crease verb has always written them.
      fmap (drop 8 . edgesFoldAngle . fst) (creaseAllAlongWith FlatForAssignment diagonalBatch cp)
        `shouldBe` Right [180, 180, -180, -180, -180]

    -- With no angles recorded, the old valley's two pieces are written at
    -- the +180 folding read off its letter, and the new mountain's at 0. Left
    -- absent, folding would read the mountain's letter too and fold it to
    -- -180. Turns red if the array stayed absent.
    it "writes the whole angle array for a file that had none (R-05-8)" $
      case creaseAllAlongWith AtRest [(V2 0 1, V2 1 0, Mountain)] lettered of
        Left err -> expectationFailure (show err)
        Right (s, pieces) -> do
          pieces `shouldBe` [[EdgeId 6, EdgeId 7]]
          edgesFoldAngle s `shouldBe` [0, 0, 0, 0, 180, 180, 0, 0]

    -- What drawing at rest is for: the paper folds exactly as it did, every
    -- old vertex landing where it was. On the diagonal pattern, folded along
    -- its own valley; on the lettered square, whose angles come from its
    -- letters; on the quarter fold, folded in quarters; and on the bare
    -- square. Turns red if a new crease were given its letter's angle, or an
    -- absent array left absent.
    it "leaves the folded paper where it was (05 L2's last row)" $ do
      cp <- fromExamples "diagonal-cp.fold"
      quarter <- fixture "quarter-fold.fold"
      let cases =
            [ (cp, diagonalBatch),
              (lettered, [(V2 0 1, V2 1 0, Mountain)]),
              (quarter, [(V2 0 0, V2 1 1, Valley)]),
              (square, [(V2 0.5 0, V2 0.5 1, Mountain), (V2 0 0.5, V2 1 0.5, Valley)])
            ]
      mapM_ (\(input, batch) -> either (expectationFailure . show) (foldsAlike input . fst) (creaseAllAlongWith AtRest batch input)) cases

  describe "what drawing a crease invalidates" $
    it "re-derives the faces and drops the keys it cannot vouch for" $ do
      -- The line cuts at least one face in two, so every face the file
      -- recorded is wrong the moment it is drawn, and so is anything in
      -- frameExtras that indexes a face or an edge.
      fr <- fixture "quarter-fold.fold"
      let vendored =
            fr
              { frameExtras = KM.fromList [("cpedit:page", Aeson.String "A4")],
                faceOrders = [FaceOrder (FaceId 0) (FaceId 1) Above]
              }
      case creaseAlong (V2 0 0) (V2 1 1) Valley vendored of
        Left err -> expectationFailure (show err)
        Right s -> do
          facesVertices s `shouldNotBe` facesVertices fr
          length (facesVertices s) `shouldBe` 6
          -- The orders name faces that no longer exist and were read against
          -- the winding of faces that no longer exist either.
          faceOrders s `shouldBe` []
          -- Checked on a frame that really carries an unrecognised key: the
          -- fixtures carry none, so asserting this on one of them is an
          -- assertion that was already true before creasing.
          frameExtras s `shouldBe` mempty

  describe "drawing several at once" $ do
    it "puts two creases on the sheet in one pass" $ do
      -- The batch form exists for speed -- cutting and tracing once instead of
      -- once per crease -- so what has to be pinned is that it draws the same
      -- thing.
      case creaseAllAlong
        [ (V2 0.5 0, V2 0.5 1, Mountain),
          (V2 0 0.5, V2 1 0.5, Valley)
        ]
        square of
        Left err -> expectationFailure (show err)
        Right out -> do
          -- Four sides cut in two, the two new creases cut at their crossing,
          -- and the middle is one vertex.
          length (verticesCoords out) `shouldBe` 9
          length (edgesVertices out) `shouldBe` 12
          drop 8 (edgesAssignment out) `shouldBe` [Mountain, Mountain, Valley, Valley]

    it "joins two creases that end at the same new point" $ do
      -- The one thing a batch has to do that a single crease never does. Both
      -- of these end at the middle of the right-hand side, which no corner
      -- occupies yet; resolving the ends independently would put two vertices
      -- there, joined to nothing, and the tracing would refuse the drawing.
      case creaseAllAlong
        [ (V2 0 0, V2 1 0.5, Valley),
          (V2 0 1, V2 1 0.5, Mountain)
        ]
        square of
        Left err -> expectationFailure (show err)
        Right out -> do
          length (verticesCoords out) `shouldBe` 5
          creasesOf out `shouldBe` [(0, 1), (1, 4), (4, 2), (2, 3), (3, 0), (0, 4), (3, 4)]

    it "decides every refusal against the frame as it was" $ do
      -- Order-independence, chosen over the case it forbids: the second crease
      -- here would meet the first if they were drawn in turn, and does not meet
      -- the paper. Drawn together, neither end of it meets anything -- and both
      -- orderings are asserted, since "does not depend on which was listed
      -- first" is the claim.
      let diagonal = (V2 0 0, V2 1 1, Valley)
          hanging = (V2 0.5 0.5, V2 0.75 0.75, Mountain)
          refused = Left (CreaseEndMeetsNothing FromEnd (V2 0.5 0.5))
      creaseAllAlong [diagonal, hanging] square `shouldBe` refused
      creaseAllAlong [hanging, diagonal] square `shouldBe` refused

    it "refuses the same crease asked for twice, naming the points" $
      -- The cutting would refuse this as two edges joining one pair of
      -- vertices, naming indices 4 and 5 -- creases that exist only inside the
      -- call, on a file with four edges. Naming an index the reader can go and
      -- fail to find is the thing this module is built not to do.
      creaseAllAlong [(V2 0 0, V2 1 1, Valley), (V2 0 0, V2 1 1, Valley)] square
        `shouldBe` Left (CreaseRepeated (V2 0 0) (V2 1 1))

    it "refuses the same crease given the other way round too" $
      -- Guards the test above: comparing the pair of ids without allowing for
      -- the reversal would let this through to the cutting.
      creaseAllAlong [(V2 0 0, V2 1 1, Valley), (V2 1 1, V2 0 0, Mountain)] square
        `shouldBe` Left (CreaseRepeated (V2 1 1) (V2 0 0))

    it "still refuses a folded form when there is nothing to draw" $ do
      -- The empty batch is a short circuit, and it must not be one that skips
      -- the refusals. A caller that computed no creases should hear the same
      -- answer about the frame as one that computed some.
      fr <- fixture "simple.fold"
      creaseAllAlong [] fr `shouldBe` Left SheetIsFolded

    it "leaves the pattern alone when there is nothing to draw" $
      -- Not "validate and hand back with the faces dropped", which is what
      -- falling through to the cutting would do.
      creaseAllAlong [] square `shouldBe` Right square

  describe "creases it will not draw" $ do
    it "refuses one with no length, without naming an edge the file has not got" $
      -- The offending element is the request. Borrowing EdgeWithoutLength
      -- named edge 4 of a four-edge file, which the reader can only go and
      -- fail to find.
      creaseAlong (V2 0.5 0.5) (V2 0.5 0.5) Valley square
        `shouldBe` Left (CreaseWithoutLength (V2 0.5 0.5) (V2 0.5 0.5))

    it "refuses an end off the paper" $ do
      -- Named for what it is, not for what it does to the faces. The first end
      -- is a corner, so it is the second that fails -- which also pins that the
      -- end is carried rather than always reported as the first.
      creaseAlong (V2 0 0) (V2 3 3) Valley square
        `shouldBe` Left (CreaseEndMeetsNothing ToEnd (V2 3 3))

    it "refuses an end in the middle of the paper the same way" $ do
      -- The case that stops the tempting message. Both ends are squarely on the
      -- sheet, so "that end is off the paper" would be a false thing to say --
      -- and the old refusal, a vertex with one crease at it, was the same
      -- sentence for both. What is true of both is that neither end meets
      -- anything.
      creaseAlong (V2 0.3 0.3) (V2 0.7 0.7) Valley square
        `shouldBe` Left (CreaseEndMeetsNothing FromEnd (V2 0.3 0.3))

    it "allows an end part-way along a crease that is already there" $ do
      -- The carve-out, and the thing a tightening of this check would silently
      -- take away. quarter-fold.fold has four creases running from the middle
      -- to the edge midpoints; an end half way down one of them meets it, so
      -- the drawing is sound and whether it folds is #76's question. Tightening
      -- the test to corners, or to border edges, would refuse this.
      fr <- fixture "quarter-fold.fold"
      case creaseAlong (V2 0.5 0.25) (V2 1 0.25) Valley fr of
        Left err -> expectationFailure ("expected a crease, got " <> show err)
        Right out -> length (edgesVertices out) `shouldBe` 15

    it "refuses two ends that resolve to one corner, as a crease with no length" $ do
      -- Further apart than the tolerance, and both within the tolerance of the
      -- corner at the origin, so the crease would run from vertex 0 to vertex 0.
      -- The refusal for that names an edge index the file does not have, which
      -- is exactly what this module is trying not to do.
      creaseAlong (V2 (-1.4e-9) 0) (V2 1.4e-9 0) Valley square
        `shouldBe` Left (CreaseWithoutLength (V2 (-1.4e-9) 0) (V2 1.4e-9 0))

    it "says so in the message, since that is the whole of this refusal" $ do
      -- Fixed point, not `show`: a coordinate typed as 0.01 has to read back as
      -- 0.01 and not as 1.0e-2, since being recognised as one of the two the
      -- caller passed in is the number's whole job.
      renderFoldError (CreaseEndMeetsNothing ToEnd (V2 0.01 3))
        `shouldBe` ( "the end at (0.01, 3.0) does not meet any crease or edge the"
                       <> " pattern already has, so the crease would stop there and"
                       <> " divide nothing"
                   )

    it "refuses to crease a folded form" $ do
      -- Creasing one means creasing through its layers, which is a different
      -- and much harder move: the line has to be cut into one crease per
      -- layer, and where those land on the flat sheet depends on the fold.
      fr <- fixture "simple.fold"
      creaseAlong (V2 0 0) (V2 1 1) Valley fr `shouldBe` Left SheetIsFolded

    it "refuses one drawn exactly on top of a crease already there" $
      -- End for end on an existing crease: nothing crosses, so nothing is cut,
      -- and what comes out is two creases between one pair of corners. That is
      -- the repeated edge Senbazuru.Fold.Faces refuses -- and it names the two
      -- creases the file has, which is the reason cutting leaves this case to
      -- it rather than reporting it itself.
      creaseAlong (V2 0 0) (V2 1 0) Valley square
        `shouldBe` Left (EdgeRepeated (EdgeId 0) (EdgeId 4))

    it "refuses one drawn along part of a crease already there" $
      -- The other shape of the same mistake, and the one cutting does have to
      -- catch: the new crease covers half the bottom edge, so that edge is cut
      -- at its far end and one of the pieces comes out doubled. Along the
      -- stretch the two share there are two answers to how the paper folds,
      -- and picking one is not senbazuru's to do.
      creaseAlong (V2 0 0) (V2 0.5 0) Valley square
        `shouldBe` Left (EdgesOverlap (EdgeId 0) (EdgeId 4))
