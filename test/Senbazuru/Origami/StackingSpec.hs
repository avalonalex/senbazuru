-- |
-- Tests for working out which layer is on top.
--
-- The answers here are stated as the order to paint the faces in, seen from
-- above and bottom layer first, because that is what a person can check with a
-- strip of paper. 'paintOrder' turns the solver's @faceOrders@ into that list,
-- which also means every test exercises the same round trip the renderer
-- makes: the sign written against a face's normal here is read back against
-- the same normal there.
--
-- Two fixtures do most of the work. The quarter fold has one stacking and it
-- is forced, so the answer is exact. The letter fold has four assignments for
-- the same folded coordinates, and two of them are impossible: the third panel
-- is longer than the first two, so it can lie on top of them or under them but
-- not slide in between, because the fold it would have to pass is closed.
module Senbazuru.Origami.StackingSpec (spec) where

import Data.ByteString qualified as BS
import Data.List (elemIndex)
import Senbazuru.Fold.Load (decodeFoldFile)
import Senbazuru.Fold.Query (FoldError (..), frameFaces)
import Senbazuru.Fold.Types
  ( Assignment (..),
    FaceId (..),
    FaceOrder (..),
    Frame (..),
    Stacking (..),
    VertexId (..),
    allFrames,
    emptyFrame,
    keyFrame,
  )
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Folding (foldFrame)
import Senbazuru.Origami.Layers (paintOrder)
import Senbazuru.Origami.Stacking
import Test.Hspec

loadFile :: FilePath -> IO [Frame]
loadFile path = do
  bytes <- BS.readFile path
  case decodeFoldFile bytes of
    Left err -> fail ("decode failed: " <> err)
    Right f -> pure (allFrames f)

loadFixture :: FilePath -> IO Frame
loadFixture path = do
  bytes <- BS.readFile path
  case decodeFoldFile bytes of
    Left err -> fail ("decode failed: " <> err)
    Right f -> pure (keyFrame f)

foldOrFail :: Frame -> IO Frame
foldOrFail fr = case foldFrame fr of
  Left err -> fail ("fold failed: " <> show err)
  Right folded -> pure folded

-- | The faces of a flat-folded frame in the order to paint them seen from
-- above: bottom layer first, top layer last.
bottomToTop :: Frame -> Either StackingError [Int]
bottomToTop fr = do
  orders <- solveStacking fr
  faces <- refused (frameFaces fr)
  map unFaceId <$> refused (paintOrder (V3 0 0 1) faces orders)
  where
    refused = either (Left . StackingRefused) Right

-- | Give every crease of a frame the assignment and flat angle listed, in
-- edge order, leaving borders alone.
withCreases :: [Assignment] -> Frame -> Frame
withCreases creases fr =
  fr
    { edgesAssignment = borders <> creases,
      edgesFoldAngle = map (const 0) borders <> map angle creases
    }
  where
    borders = filter (== Border) (edgesAssignment fr)
    angle = \case
      Valley -> 180
      Mountain -> -180
      _ -> 0

-- | A unit square with one crease down the middle, as a crease pattern.
halfSheet :: Assignment -> Frame
halfSheet assignment =
  emptyFrame
    { verticesCoords = [[0, 0], [0.5, 0], [1, 0], [1, 1], [0.5, 1], [0, 1]],
      edgesVertices =
        [ (VertexId 0, VertexId 1),
          (VertexId 1, VertexId 2),
          (VertexId 2, VertexId 3),
          (VertexId 3, VertexId 4),
          (VertexId 4, VertexId 5),
          (VertexId 5, VertexId 0),
          (VertexId 1, VertexId 4)
        ],
      edgesAssignment = replicate 6 Border <> [assignment],
      facesVertices = [map VertexId [0, 1, 4, 5], map VertexId [1, 2, 3, 4]]
    }

-- | Two unit squares one above the other in the same plane, not joined by any
-- crease: nothing in the paper says which is on top.
looseLeaves :: Frame
looseLeaves =
  emptyFrame
    { frameClasses = ["foldedForm"],
      verticesCoords = [[0, 0], [1, 0], [1, 1], [0, 1], [0, 0], [1, 0], [1, 1], [0, 1]],
      edgesVertices = [(VertexId a, VertexId b) | (a, b) <- [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4)]],
      edgesAssignment = replicate 8 Border,
      facesVertices = [map VertexId [0, 1, 2, 3], map VertexId [4, 5, 6, 7]]
    }

-- | Does @a@ come before @b@ in the list?
precedes :: Int -> Int -> [Int] -> Bool
precedes a b xs = case (elemIndex a xs, elemIndex b xs) of
  (Just i, Just j) -> i < j
  _ -> False

spec :: Spec
spec = do
  describe "one crease" $ do
    it "puts the moving face on top for a valley" $ do
      -- A valley brings the two top sides together, so the half that folded
      -- over lands on top of the half that stayed.
      folded <- foldOrFail (halfSheet Valley)
      bottomToTop folded `shouldBe` Right [0, 1]

    it "puts it underneath for a mountain" $ do
      folded <- foldOrFail (halfSheet Mountain)
      bottomToTop folded `shouldBe` Right [1, 0]

    it "writes the sign against the second face's normal, as FOLD does" $ do
      -- Face 1 folded over, so it lies top-down and its normal points -z. Face
      -- 0 is below it in space, which is the side that normal points to: above,
      -- relative to face 1. Reading the same entry back with paintOrder is the
      -- test above; this one pins the wire format.
      folded <- foldOrFail (halfSheet Valley)
      solveStacking folded `shouldBe` Right [FaceOrder (FaceId 0) (FaceId 1) Above]

  describe "the quarter fold" $ do
    it "stacks its four layers in the one order the creases allow" $ do
      -- Fold the left half behind (mountain), then the top half down towards
      -- you (valley). The back layer's crease is a mountain seen from the
      -- pattern's side, which is why the file has three. Bottom to top: the
      -- bottom-left quadrant, the bottom-right, the top-right, the top-left.
      flat <- loadFixture "test/fixtures/quarter-fold.fold"
      folded <- foldOrFail flat
      bottomToTop folded `shouldBe` Right [3, 0, 1, 2]

    it "mirrors the stack when every assignment is swapped" $ do
      -- The same rigid motions -- at 180 degrees a mountain and a valley move
      -- the paper identically -- and the opposite picture, which is the whole
      -- reason the assignment is kept.
      flat <- loadFixture "test/fixtures/quarter-fold.fold"
      folded <- foldOrFail flat {edgesFoldAngle = map negate (edgesFoldAngle flat)}
      bottomToTop folded `shouldBe` Right [2, 1, 0, 3]

    it "orders the half-folded step, where only two pairs overlap" $ do
      -- Frame 1 of the sequence: the left half folded behind. Faces 3 and 2
      -- lie under 0 and 1 respectively, and nothing relates the left pair to
      -- the right pair because they do not overlap.
      frames <- loadFile "test/fixtures/quarter-fold-steps.fold"
      halfFolded <- case drop 1 frames of
        (fr : _) -> pure fr
        [] -> fail "fixture has no second frame"
      fmap length (solveStacking halfFolded) `shouldBe` Right 2
      order <- either (fail . show) pure (bottomToTop halfFolded)
      order `shouldSatisfy` precedes 3 0
      order `shouldSatisfy` precedes 2 1

  describe "the letter fold" $ do
    -- Panels of width 0.3, 0.2 and 0.5. The middle panel folds onto the first;
    -- the third, being longer than both, sticks out past the fold between them.
    let lettered creases = withCreases creases <$> loadFixture "test/fixtures/letter-fold.fold"

    it "folds into an accordion when the creases alternate" $ do
      folded <- lettered [Valley, Mountain] >>= foldOrFail
      bottomToTop folded `shouldBe` Right [0, 1, 2]
      mirrored <- lettered [Mountain, Valley] >>= foldOrFail
      bottomToTop mirrored `shouldBe` Right [2, 1, 0]

    it "refuses to roll it, because the long panel cannot pass the closed fold" $ do
      -- Two valleys ask the third panel to go between the first two. It is
      -- longer than the pocket, and the pocket is closed at the far end.
      -- Folding cannot see this: the coordinates are identical to the
      -- accordion's. Only the layers know.
      rolled <- lettered [Valley, Valley] >>= foldOrFail
      case solveStacking rolled of
        Left (StackingRefused (Unstackable _)) -> pure ()
        other -> expectationFailure ("expected an unstackable model, got " <> show other)
      rolledTheOtherWay <- lettered [Mountain, Mountain] >>= foldOrFail
      case solveStacking rolledTheOtherWay of
        Left (StackingRefused (Unstackable _)) -> pure ()
        other -> expectationFailure ("expected an unstackable model, got " <> show other)

    it "states the rule that forbids the roll" $ do
      -- Taco-tortilla: the first panel runs across the line the second and
      -- third are folded on, and the third runs across the line the first and
      -- second are folded on. Neither may lie between the other two.
      folded <- lettered [Valley, Valley] >>= foldOrFail
      rules <- either (fail . show) pure (stackingRules folded)
      rules `shouldSatisfy` any (forbidsBetween 0 1 2)
      rules `shouldSatisfy` any (forbidsBetween 2 0 1)
      -- And all three share paper, so their orders may not run in a circle.
      rules `shouldSatisfy` elem (Acyclic (FaceId 0) (FaceId 1) (FaceId 2))

  describe "the big-little-big counterexample" $
    it "is refused, which the single-vertex theorems cannot do" $ do
      -- Passes Maekawa and Kawasaki, folds without tearing, and still cannot
      -- exist: the small sector's two neighbours both fold to the same side of
      -- it, and each runs across the other's crease.
      flat <- loadFixture "test/fixtures/big-little-big.fold"
      folded <- foldOrFail flat
      case solveStacking folded of
        Left (StackingRefused (Unstackable _)) -> pure ()
        other -> expectationFailure ("expected an unstackable model, got " <> show other)

  describe "what it declines" $ do
    it "declines a model that is still in the air" $ do
      folded <- loadFixture "test/fixtures/simple.fold"
      case solveStacking folded of
        Left (NotFlat dz) -> dz `shouldSatisfy` (> 0)
        other -> expectationFailure ("expected NotFlat, got " <> show other)

    it "declines a face that is not convex" $ do
      let ell =
            emptyFrame
              { frameClasses = ["foldedForm"],
                verticesCoords = [[0, 0], [2, 0], [2, 1], [1, 1], [1, 2], [0, 2]],
                edgesVertices = [(VertexId a, VertexId b) | (a, b) <- [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 0)]],
                edgesAssignment = replicate 6 Border,
                facesVertices = [map VertexId [0 .. 5]]
              }
      solveStacking ell `shouldBe` Left (NonConvexFace (FaceId 0))

  describe "what it refuses" $ do
    it "refuses windings that disagree across a crease" $ do
      -- The two halves of a folded sheet must wind opposite ways, because the
      -- winding says which side is up and one of them has been turned over.
      -- Listing them the same way round is a file contradicting itself, and
      -- every sign in the answer would be read against it.
      folded <- foldOrFail (halfSheet Valley)
      let clashing = folded {facesVertices = map reverse (take 1 (facesVertices folded)) <> drop 1 (facesVertices folded)}
      solveStacking clashing `shouldBe` Left (StackingRefused (WindingClash (FaceId 1) (FaceId 0)))

    it "refuses an edges_foldAngle of the wrong length" $ do
      folded <- foldOrFail (halfSheet Valley)
      solveStacking folded {edgesFoldAngle = [180]}
        `shouldBe` Left (StackingRefused (ArrayLengthMismatch "edges_vertices" 7 "edges_foldAngle" 1))

  describe "what it leaves alone" $ do
    it "orders nothing when no faces overlap" $ do
      -- A flat frame that calls itself folded but whose faces tile the sheet.
      -- The answer is empty and it is an answer: any order paints the same
      -- picture.
      solveStacking (halfSheet Valley) {frameClasses = ["foldedForm"]} `shouldBe` Right []

    it "orders nothing when there are no faces" $
      solveStacking emptyFrame {verticesCoords = [[0, 0], [1, 1]]} `shouldBe` Right []

    it "picks the lower id for a pair no rule reaches, and says so consistently" $
      -- Two loose squares, one on the other, joined by nothing: the paper has
      -- no opinion. The solver has to say something for the picture to be
      -- drawn, and what it says is fixed and reproducible rather than merely
      -- arbitrary.
      bottomToTop looseLeaves `shouldBe` Right [1, 0]
  where
    forbidsBetween t a b = \case
      NotBetween t' a' b' -> FaceId t == t' && ((FaceId a, FaceId b) == (a', b') || (FaceId b, FaceId a) == (a', b'))
      _ -> False
