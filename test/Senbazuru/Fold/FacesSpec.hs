-- |
-- Tests for tracing a frame's faces from its creases.
--
-- The strongest evidence here is not a hand-written expectation but the ten
-- fixtures that /do/ record @faces_vertices@: tracing their edges has to give
-- back exactly the faces their authors wrote, ring for ring. That is 72 faces
-- on the crane and 25 on a grid, none of them chosen by us, and getting the
-- turn at a vertex backwards or dropping the wrong ring fails it immediately.
--
-- The property test covers what fixtures cannot: that nothing is missed. A
-- grid of creases has a known number of cells whose areas are known to sum to
-- the sheet, so a trace that quietly loses a face, or keeps the outside of the
-- sheet as though it were paper, is caught by arithmetic rather than by
-- someone having thought to write that case down.
--
-- The rest is refusals. Each has its own test because each names a different
-- element of the file, and \"it was refused\" is not the useful half of that.
module Senbazuru.Fold.FacesSpec (spec) where

import Data.ByteString qualified as BS
import Data.List (nub, sort)
import Senbazuru.Fold.Faces
import Senbazuru.Fold.Load (decodeFile, renderLoadError)
import Senbazuru.Fold.Query (FoldError (..), frameFaceOrders, renderFoldError)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (signedArea)
import Test.Hspec
import Test.QuickCheck

-- | Every fixture that records its own faces, so tracing can be checked
-- against them.
fixturesWithFaces :: [FilePath]
fixturesWithFaces =
  [ "bad-twist",
    "big-little-big",
    "crane",
    "diagonal-cp",
    "grid-2x2-d1",
    "kabuto",
    "letter-fold",
    "quarter-fold",
    "quarter-fold-steps",
    "thirds-pinwheel"
  ]

-- | Load a fixture's key frame, in whatever format it is in.
fixture :: FilePath -> IO Frame
fixture name = do
  let path = "test/fixtures/" <> name
  bytes <- BS.readFile path
  case decodeFile path bytes of
    Left err -> fail (show (renderLoadError err))
    Right f -> pure (keyFrame f)

-- | A ring rotated to start at its lowest vertex id.
--
-- Which corner a ring starts at is arbitrary — it is whichever half-edge the
-- walk happened to begin from — so a comparison against a file's own faces has
-- to be up to rotation, and this is what makes that a plain equality. The
-- direction is /not/ normalised, because that is not arbitrary: every traced
-- ring is anticlockwise, and a test that threw the winding away could not see
-- it go backwards.
fromLowest :: [VertexId] -> [Int]
fromLowest ring = take (length ids) (drop start (cycle ids))
  where
    ids = map unVertexId ring
    lowest = minimum ids
    start = length (takeWhile (/= lowest) ids)

-- | The error from a refusal, for asserting on the message rather than the
-- constructor.
leftOf :: Either a b -> Maybe a
leftOf = either Just (const Nothing)

-- | A square of paper with the given creases and no faces recorded.
sheet :: [[Double]] -> [(Int, Int)] -> Frame
sheet points es =
  emptyFrame
    { frameClasses = ["creasePattern"],
      verticesCoords = points,
      edgesVertices = [(VertexId a, VertexId b) | (a, b) <- es]
    }

-- | The unit square's four corners and four sides, which most refusal tests
-- start from and then spoil.
unitSquare :: Frame
unitSquare = sheet [[0, 0], [1, 0], [1, 1], [0, 1]] [(0, 1), (1, 2), (2, 3), (3, 0)]

-- | A grid of creases: interior cuts across a unit square, both ways.
--
-- Cuts are tenths, so no two grid lines are closer than a tenth and no edge
-- comes out degenerate — which keeps the generator's job to \"how many cells,
-- and how uneven\", the two things the trace actually has to cope with.
newtype Grid = Grid ([Double], [Double])
  deriving stock (Eq, Show)

instance Arbitrary Grid where
  arbitrary = do
    xs <- cuts
    ys <- cuts
    pure (Grid (xs, ys))
    where
      cuts = do
        n <- choose (0, 4 :: Int)
        interior <- vectorOf n (choose (1, 9 :: Int))
        pure (0 : map ((/ 10) . fromIntegral) (nub (sort interior)) <> [1])

  -- Dropping an interior cut removes a row or a column, which is the smallest
  -- step towards the smallest failing grid. See docs/notes/shrinking.md.
  shrink (Grid (xs, ys)) =
    [Grid (xs', ys) | xs' <- dropOne xs]
      <> [Grid (xs, ys') | ys' <- dropOne ys]
    where
      dropOne cs =
        [ take i cs <> drop (i + 1) cs
          | i <- [1 .. length cs - 2]
        ]

-- | The grid as a frame: a vertex at every crossing, an edge between every
-- pair of neighbours.
gridFrame :: Grid -> Frame
gridFrame (Grid (xs, ys)) = sheet points (across <> down)
  where
    nx = length xs
    ny = length ys
    at i j = j * nx + i
    points = [[x, y] | y <- ys, x <- xs]
    across = [(at i j, at (i + 1) j) | j <- [0 .. ny - 1], i <- [0 .. nx - 2]]
    down = [(at i j, at i (j + 1)) | j <- [0 .. ny - 2], i <- [0 .. nx - 1]]

-- | The area of a traced ring, read off the frame it came from.
--
-- 'Nothing' rather than a shorter polygon if any corner cannot be resolved. A
-- comprehension that filtered the bad corner out would quietly measure a
-- different shape — which is exactly the failure the property below exists to
-- catch, so it must not be able to hide inside the measurement.
areaOf :: Frame -> [VertexId] -> Maybe Double
areaOf fr ring = signedArea <$> traverse corner ring
  where
    corner (VertexId v) = case take 1 (drop v (verticesCoords fr)) of
      [x : y : _] -> Just (V2 x y)
      _ -> Nothing

spec :: Spec
spec = do
  describe "tracing the faces a file already records" $
    mapM_ reproduces fixturesWithFaces

  describe "tracing the faces a file does not record" $ do
    it "cuts three-crease.fold into the three regions its creases make" $ do
      fr <- fixture "three-crease.fold"
      -- Vertex 5 sits at the middle of the sheet with creases to 4, 2 and 3,
      -- which cut it into a left piece, a right piece and a top piece.
      fmap (map fromLowest) (traceFaces fr)
        `shouldBe` Right [[0, 4, 5, 3], [1, 2, 5, 4], [2, 3, 5]]

    it "gives the bird base the fourteen faces its .cp file cannot" $ do
      -- The reason #35 said this issue was what it was waiting for: no .cp can
      -- record a face, so until now nothing read from one could be folded.
      fr <- fixture "bird-base.cp"
      fmap length (traceFaces fr) `shouldBe` Right 14

    it "winds every face anticlockwise, whatever the file did" $ do
      -- The sign is what selects the faces from the rings, so it is not a
      -- coincidence -- but it is a promise the module header makes and that
      -- Origami.Folding relies on, so it is worth one assertion.
      fr <- fixture "crane.fold"
      case traceFaces fr of
        Left err -> expectationFailure (show err)
        Right rings -> map (fmap signum . areaOf fr) rings `shouldBe` replicate 72 (Just 1)

  describe "a grid of creases" $ do
    it "traces one face per cell" $
      property $ \g@(Grid (xs, ys)) ->
        fmap length (traceFaces (gridFrame g))
          === Right ((length xs - 1) * (length ys - 1))

    it "traces faces whose areas add up to the whole sheet" $
      -- What no fixture can check: that nothing was missed and nothing was
      -- counted twice. A trace that dropped a cell, or kept the outside of the
      -- sheet as though it were paper, lands somewhere other than 1.
      property $ \g ->
        let fr = gridFrame g
         in case traceFaces fr of
              Left err -> counterexample (show err) False
              Right rings -> case traverse (areaOf fr) rings of
                Nothing -> counterexample "a traced ring named a corner the frame does not have" False
                Just areas ->
                  let total = sum areas
                   in counterexample (show total) (abs (total - 1) < 1e-9)

  describe "drawings it will not trace" $ do
    it "refuses a folded form that has left the plane" $ do
      fr <- fixture "simple.fold"
      traceFaces fr `shouldBe` Left SheetIsFolded

    it "refuses a form folded flat, which its coordinates alone do not give away" $ do
      -- The case relief cannot catch, and the one that matters: a model folded
      -- flat has coordinates a crease pattern's cannot be told from, so only
      -- frame_classes says what it is. Tracing it would report the regions of
      -- a drawing in which the paper lies on top of itself -- and every one of
      -- the checks below would pass, because a self-overlapping drawing is not
      -- malformed, only meaningless.
      let overlapped =
            (sheet [[0, 0], [1, 0], [1, 1], [0, 1]] [(0, 1), (1, 2), (2, 3), (3, 0)])
              { frameClasses = ["foldedForm"]
              }
      traceFaces overlapped `shouldBe` Left SheetIsFolded

    it "refuses an edge naming a vertex that is not there, as frameCreases does" $ do
      -- frameVertices resolves coordinates and nothing else, so this gets past
      -- it. Unchecked, vertex 7 was given a phantom position at the origin and
      -- the refusal that followed named whichever innocent element it landed
      -- on -- here vertex 0 and edge 5, neither of which is wrong.
      let phantom =
            sheet
              [[10, 10], [11, 10], [11, 11], [10, 11]]
              [(0, 1), (1, 2), (2, 3), (3, 0), (0, 7), (7, 2)]
      traceFaces phantom
        `shouldBe` Left (VertexIndexOutOfRange (EdgeId 4) (VertexId 7) 4)

    it "refuses a crease with the same paper on both sides of it" $ do
      -- An island joined to the sheet by one crease. Every degree is two or
      -- more, nothing crosses, nothing is disconnected -- so every check on
      -- the drawing passes, and the trace still comes back with a ring shaped
      -- like a keyhole that lists both ends of the bridge twice. A face like
      -- that is its own neighbour across that edge.
      let island =
            sheet
              [[0, 0], [4, 0], [4, 4], [0, 4], [1, 1], [3, 1], [3, 3], [1, 3]]
              [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4), (0, 4)]
      traceFaces island `shouldBe` Left (CreaseBridge (VertexId 0) (VertexId 4))

    it "refuses a vertex no crease uses, and says that rather than something else" $ do
      -- Degree nought and degree one are the same constructor and not the same
      -- complaint: nothing stops in the middle of the paper here, the vertex
      -- is simply unused.
      let stray = sheet [[0, 0], [1, 0], [1, 1], [0, 1], [5, 5]] [(0, 1), (1, 2), (2, 3), (3, 0)]
      traceFaces stray `shouldBe` Left (VertexTooFewCreases (VertexId 4) 0)
      fmap renderFoldError (leftOf (traceFaces stray))
        `shouldBe` Just "vertex 4 is not an end of any crease, so it is not a corner of anything"

    it "refuses creases that cross with no vertex where they meet" $ do
      -- unit-square.fold's three interior creases all pass through the middle
      -- of the sheet and none of them stops there.
      fr <- fixture "unit-square.fold"
      traceFaces fr `shouldBe` Left (EdgesCross (EdgeId 8) (EdgeId 9))

    it "refuses a vertex sitting on an edge that does not end there" $ do
      -- The T-junction: two creases meet the bottom of the paper at a point,
      -- but the bottom was never split in two there. Every vertex has creases
      -- enough, so nothing else catches it; the walk goes straight past the
      -- junction and puts it on the wrong side of the sheet's own edge.
      let tee =
            sheet
              [[0, 0], [1, 0], [1, 1], [0, 1], [0.5, 0]]
              [(0, 1), (1, 2), (2, 3), (3, 0), (4, 3), (4, 2)]
      traceFaces tee `shouldBe` Left (VertexInsideEdge (VertexId 4) (EdgeId 0))

    it "refuses an edge with no length, which points nowhere" $ do
      let doubled =
            sheet
              [[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]]
              [(0, 1), (1, 2), (2, 3), (3, 0), (0, 4)]
      traceFaces doubled `shouldBe` Left (EdgeWithoutLength (EdgeId 4))

    it "refuses two edges between the same pair of vertices" $ do
      -- They lie at the same angle around both ends, so which one the walk
      -- should turn onto is a coin toss.
      let twice = unitSquare {edgesVertices = edgesVertices unitSquare <> [(VertexId 0, VertexId 1)]}
      traceFaces twice `shouldBe` Left (EdgeRepeated (EdgeId 0) (EdgeId 4))

    it "refuses a crease that stops in the middle of the paper" $ do
      let spur =
            sheet
              [[0, 0], [1, 0], [1, 1], [0, 1], [0.5, 0.5]]
              [(0, 1), (1, 2), (2, 3), (3, 0), (0, 4)]
      traceFaces spur `shouldBe` Left (VertexTooFewCreases (VertexId 4) 1)

    it "refuses a sheet in two pieces" $ do
      let apart =
            sheet
              [[0, 0], [1, 0], [1, 1], [0, 1], [2, 0], [3, 0], [3, 1], [2, 1]]
              [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4)]
      traceFaces apart `shouldBe` Left (SheetInPieces (VertexId 0) (VertexId 4))

    it "has no faces for a sheet nobody has creased" $
      traceFaces (sheet [[0, 0], [1, 0]] []) `shouldBe` Right []

  describe "withTracedFaces" $ do
    it "leaves a frame that already records faces exactly as it found it" $ do
      -- Those faces came with a winding, and a faceOrders read against it may
      -- have come with them; recomputing here would turn a model inside out.
      fr <- fixture "simple.fold"
      withTracedFaces fr `shouldBe` Right fr

    it "fills in the faces of one that does not" $ do
      fr <- fixture "three-crease.fold"
      fmap (length . facesVertices) (withTracedFaces fr) `shouldBe` Right 3

    it "leaves alone a frame whose faceOrders name faces it never recorded" $ do
      -- Malformed, and refused as such before there was any tracing. Tracing
      -- underneath those orders would not fix the file, it would silence it:
      -- they would be range-checked against faces they were never written for,
      -- quite possibly pass, and describe the stacking of some other model.
      let orders =
            (sheet [[0, 0], [1, 0], [1, 1], [0, 1]] [(0, 1), (1, 2), (2, 3), (3, 0)])
              { faceOrders = [FaceOrder (FaceId 0) (FaceId 1) Above]
              }
      -- No faces invented,
      fmap facesVertices (withTracedFaces orders) `shouldBe` Right []
      -- and the refusal the file has always earned still arrives.
      (frameFaceOrders =<< withTracedFaces orders)
        `shouldBe` Left (FaceOrderOutOfRange (FaceId 0) 0)
  where
    reproduces name =
      it ("reproduces " <> name <> ".fold's own faces_vertices") $ do
        fr <- fixture (name <> ".fold")
        fmap (sort . map fromLowest) (traceFaces fr)
          `shouldBe` Right (sort (map fromLowest (facesVertices fr)))
