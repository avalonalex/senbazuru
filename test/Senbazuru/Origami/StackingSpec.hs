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

import Control.Monad (forM_)
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
import Senbazuru.Origami.FlatFold (Report (..), checkFrame, defaultTolerance)
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

-- | A crease-pattern fixture, folded along its own angles.
foldedFixture :: String -> IO Frame
foldedFixture name = loadFixture ("test/fixtures/" <> name <> ".fold") >>= foldOrFail

-- | The refusal several tests expect: no order of the layers exists at all.
shouldBeUnstackable :: Frame -> Expectation
shouldBeUnstackable fr = case solveStacking fr of
  Left (StackingRefused (Unstackable _)) -> pure ()
  other -> expectationFailure ("expected an unstackable model, got " <> show other)

-- | The faces of a flat-folded frame in the order to paint them seen from
-- above: bottom layer first, top layer last.
--
-- Takes the layer order 'solveStacking' picks, which is the first of each
-- component.
bottomToTop :: Frame -> Either StackingError [Int]
bottomToTop = bottomToTopAs []

-- | The same, for a chosen layer order rather than the first.
bottomToTopAs :: [Int] -> Frame -> Either StackingError [Int]
bottomToTopAs choices fr = do
  orders <- solveStackingAs defaultBudget choices fr
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

-- | How many rules of each kind, in the order Flat-Folder's table lists them:
-- taco-taco, taco-tortilla, tortilla-tortilla, transitivity. 'Fixed' rules are
-- the crease assignments and have no column there.
tally :: [Rule] -> [Int]
tally rules = [length (filter ((== k) . kind) rules) | k <- [1 .. 4 :: Int]]
  where
    kind = \case
      Fixed {} -> 0
      NoInterleave {} -> 1
      NotBetween {} -> 2
      SameOrder {} -> 3
      Acyclic {} -> 4

-- | Does @a@ come before @b@ in the list?
precedes :: Int -> Int -> [Int] -> Bool
precedes a b xs = case (elemIndex a xs, elemIndex b xs) of
  (Just i, Just j) -> i < j
  _ -> False

-- | A square folded along its diagonal: two triangles landing on each other
-- exactly, the angle between them a full valley, and nothing said about which
-- is on top. The angle is what folds it; the assignment is along for the ride,
-- since an explicit @edges_foldAngle@ takes precedence over one.
stackedTriangles :: Frame
stackedTriangles =
  emptyFrame
    { frameClasses = ["foldedForm"],
      verticesCoords = [[0, 0], [1, 0], [1, 1], [1, 0]],
      edgesVertices =
        [ (VertexId 0, VertexId 1),
          (VertexId 1, VertexId 2),
          (VertexId 2, VertexId 3),
          (VertexId 3, VertexId 0),
          (VertexId 0, VertexId 2)
        ],
      edgesAssignment = [Border, Border, Border, Border, Valley],
      edgesFoldAngle = [0, 0, 0, 0, 180],
      facesVertices = [map VertexId [0, 1, 2], map VertexId [0, 2, 3]]
    }

spec :: Spec
spec = do
  describe "which layer order to use" $ do
    it "takes the file's own when it has one" $
      -- Whatever the geometry would have said: a file that states its layers
      -- is believed, and the solver is not consulted.
      layerOrderFor defaultBudget stackedTriangles {faceOrders = [FaceOrder (FaceId 1) (FaceId 0) Above]}
        `shouldBe` Right (Just [FaceOrder (FaceId 1) (FaceId 0) Above])

    it "works one out for a flat model that has none, and the right way up" $
      -- Face 1 turned over onto face 0, so face 0 is on the side face 1's
      -- normal now points to: [0, 1, Above]. Pinned as the exact entry and not
      -- as a count, because the solver's own comment warns that a wrong crease
      -- direction mirrors the whole stack in silence, and a count of one is
      -- the same either way up.
      layerOrderFor defaultBudget stackedTriangles
        `shouldBe` Right (Just [FaceOrder (FaceId 0) (FaceId 1) Above])

    it "has none for paper still in the air" $
      -- Declined rather than refused: the solver covers models folded flat and
      -- attempted nothing here, so there is no ordering and no error either.
      layerOrderFor defaultBudget stackedTriangles {verticesCoords = [[0, 0, 0], [1, 0, 0], [1, 1, 0.5], [1, 0, 0]]}
        `shouldBe` Right Nothing

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
      folded <- foldedFixture "quarter-fold"
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

  describe "the folds with no interior vertex" $ do
    -- book-base, accordion and blintz-base are grouped in examples/README.md by
    -- two properties, and both are asserted here because both are the reason
    -- those files were chosen over other traditional folds and neither is
    -- visible in the file itself.
    --
    -- No crease meets another, so #114 can settle the fold radius and the layer
    -- separation before deciding what to draw where creases cross. And each has
    -- exactly one valid layer order, so a change to the solver cannot pick a
    -- different stacking for them without a test saying so.
    forM_ ["book-base", "accordion", "blintz-base"] $ \name -> do
      it ("has no interior vertex in " <> name) $ do
        flat <- loadFixture ("test/fixtures/" <> name <> ".fold")
        report <- either (fail . show) pure (checkFrame defaultTolerance flat)
        reportChecked report `shouldBe` []
        reportSkipped report `shouldSatisfy` (not . null)

      it ("stacks " <> name <> " exactly one way") $ do
        -- Counted rather than compared: the point is that there is nothing to
        -- choose, not which order was chosen.
        folded <- foldedFixture name
        fmap stateCount (stackingSpace defaultBudget folded) `shouldBe` Right (1, False)

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
      lettered [Valley, Valley] >>= foldOrFail >>= shouldBeUnstackable
      lettered [Mountain, Mountain] >>= foldOrFail >>= shouldBeUnstackable

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
      foldedFixture "big-little-big" >>= shouldBeUnstackable

  describe "against Flat-Folder's table" $ do
    -- Flat-Folder (MIT) ships a CSV recording, for most of its example crease
    -- patterns, how many overlapping pairs it found and how many constraints
    -- of each kind. The five columns below are copied from
    -- examples/instagram_data.csv and examples/grids_data.csv at its commit
    -- d50004815fb7: variables, taco-taco, taco-tortilla, tortilla-tortilla,
    -- transitivity. Its transitivity column counts triples with a cell of its
    -- overlap graph under all three faces, before the reduction a later column
    -- applies; ours counts triples with a common patch of paper, which is the
    -- same thing. Its taco-taco constraint spans six pairs where ours spans
    -- four -- the two taco pairs are separate Fixed rules here -- but there is
    -- one per overlapping edge pair in both, so the counts still compare.
    --
    -- Agreeing with an independent implementation, number for number, is the
    -- best evidence available that the rules are generated right. The first
    -- run of this test found six transitivity rules missing from the kabuto,
    -- which turned out to be NaN areas from a division by zero in clipping,
    -- fixed since.
    let table =
          [ ("crane", 892, [197, 712, 254, 6392]),
            ("kabuto", 117, [21, 88, 0, 420]),
            ("thirds-pinwheel", 28, [0, 28, 0, 36]),
            ("grid-2x2-d1", 132, [16, 120, 0, 332])
          ]

    mapM_
      ( \(name, variables, counts) ->
          it ("generates the same constraints for the " <> name) $ do
            fr <- foldedFixture name
            fmap length (solveStacking fr) `shouldBe` Right variables
            fmap tally (stackingRules fr) `shouldBe` Right counts
      )
      table

    it "stacks the crane, which is what the golden test draws" $ do
      fr <- foldedFixture "crane"
      order <- either (fail . show) pure (bottomToTop fr)
      length order `shouldBe` 72

    it "refuses the bad twist, which has no valid stacking" $ do
      -- From Flat-Folder's unsatisfiable/ folder: it folds without tearing and
      -- passes the single-vertex theorems, and no order of its layers exists.
      foldedFixture "bad-twist" >>= shouldBeUnstackable

    it "stacks the twists, which paintOrder still cannot paint" $ do
      -- A twist's flaps lie in a circle: A over B over C over A, with no point
      -- under all three. That is a valid stacking, and the solver finds it, but
      -- paintOrder needs one global order and there is none.
      --
      -- Not a limitation of the renderer any more -- a flat-folded model is
      -- drawn by visible region now, and draws twists perfectly well. This
      -- pins the older path, which folded forms that are not flat still take.
      mapM_
        ( \name -> do
            fr <- foldedFixture name
            case bottomToTop fr of
              Left (StackingRefused (ImpossibleStacking _)) -> pure ()
              other -> expectationFailure (name <> ": expected a painting order to be impossible, got " <> show other)
        )
        ["thirds-pinwheel", "grid-2x2-d1"]

  describe "the shape of the answer" $ do
    -- The same CSV again, four columns further along: components, states and
    -- component_assignments. Agreeing on the shape and not merely the total is
    -- the stronger check -- the crane's |1|5| says one group of pairs settled
    -- outright and one group admitting five answers, and getting that right by
    -- accident while splitting the graph wrongly is not a thing that happens.
    --
    -- Their first component is always the settled pairs, whether there are any
    -- or not, so ours is theirs minus one and 'componentCount' adds it back.
    let table =
          [ ("crane", 2, 5, [5], [8]),
            ("kabuto", 3, 9, [3, 3], [4, 4]),
            ("thirds-pinwheel", 1, 1, [], []),
            ("grid-2x2-d1", 5, 16, [2, 2, 2, 2], [2, 2, 2, 2])
          ]

    mapM_
      ( \(name, components, states, sizes, guesses) ->
          it ("splits the " <> name <> " as Flat-Folder does") $ do
            fr <- foldedFixture name
            space <- either (fail . show) pure (stackingSpace defaultBudget fr)
            componentCount space `shouldBe` components
            stateCount space `shouldBe` (states, False)
            map (length . choiceStates) (stackingsChoices space) `shouldBe` sizes
            -- Not a fact about the model but about our propagation: these are
            -- the guesses left over once it has done its work, so a change that
            -- weakened it shows up here as a bigger number rather than as a
            -- slower test.
            map choiceGuesses (stackingsChoices space) `shouldBe` guesses
      )
      table

  describe "choosing among several" $ do
    it "puts a different face of the crane on top" $ do
      -- Five orders, two pictures: the flap on the right wing is on top in one
      -- and buried in the other. This is the whole point of being able to pick.
      fr <- foldedFixture "crane"
      first' <- either (fail . show) pure (bottomToTopAs [0] fr)
      other <- either (fail . show) pure (bottomToTopAs [3] fr)
      first' `shouldNotBe` other

    it "refuses an order a component does not have" $ do
      fr <- foldedFixture "kabuto"
      solveStackingAs defaultBudget [0, 9] fr `shouldBe` Left (NoSuchStacking 1 9 3)

    it "refuses an index for a component that is not there" $ do
      -- The crane has one group with a choice in it, so a second index is a
      -- question about a different model. Zipping the lists would have dropped
      -- it without a word.
      fr <- foldedFixture "crane"
      solveStackingAs defaultBudget [0, 0] fr `shouldBe` Left (NoSuchComponent 1 1)

  describe "the budget" $ do
    it "gives up rather than running on" $ do
      -- One guess is not enough for the crane, which needs eight. No model here
      -- comes anywhere near the default, so this is the only way to reach the
      -- refusal without inventing a file built to defeat propagation -- which
      -- would not be paper.
      fr <- foldedFixture "crane"
      stackingSpace (Budget 1) fr `shouldBe` Left (StackingRefused (GaveUpStacking 1))

    it "says at least, rather than exactly, when it stops early" $ do
      -- Enough to find some of the crane's five orders and not all of them.
      fr <- foldedFixture "crane"
      space <- either (fail . show) pure (stackingSpace (Budget 5) fr)
      stateCount space `shouldSatisfy` \(n, capped) -> capped && n < 5

    it "settles every fixture here well inside the default" $ do
      -- The number that matters is the largest, and it is eight.
      forM_ ["quarter-fold", "letter-fold", "thirds-pinwheel", "grid-2x2-d1", "kabuto", "crane"] $ \name -> do
        fr <- foldedFixture name
        space <- either (fail . show) pure (stackingSpace defaultBudget fr)
        sum (map choiceGuesses (stackingsChoices space)) `shouldSatisfy` (< 10)

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
