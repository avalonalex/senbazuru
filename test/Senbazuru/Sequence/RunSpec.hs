-- | Where a run starts: 'sheetState' on the repository's sheets, and on small
-- sheets made here for the cases no fixture has, such as a crease drawn F at
-- an angle or a face wound clockwise.
module Senbazuru.Sequence.RunSpec (spec) where

import Control.Monad (forM_, void)
import Data.List (sort, sortOn)
import Data.Map.Strict qualified as M
import Data.Text qualified as T
import Senbazuru.Explain (explain)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (frameVertices)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..), norm, (^-^))
import Senbazuru.Geometry.Polygon (signedArea)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Flap (FlapError (..), flapCheck)
import Senbazuru.Origami.HingeSweep (SweepCheck (..), SweepOutcome (..), SweepSettings (..))
import Senbazuru.Origami.Surface (surfaceFrame)
import Senbazuru.Sequence.Build
import Senbazuru.Sequence.Check (checkSequence)
import Senbazuru.Sequence.Elaborate (elaborate)
import Senbazuru.Sequence.Error (FoldedBy (..), MoveFailure (..), Place (..), ResolveProblem (..), SelectionError (..), SequenceError (..), SheetProblem (..), refusalKindOf)
import Senbazuru.Sequence.Record (ExpectedRefusal (..), MaterialPoint (..), MaterialSegment (..), MoveKind (..), RouteEvidence (..), Run (..), RunStop (..), recordAfter, recordAnchor, recordAngles, recordBefore, recordEvidence, recordHinge, recordKind, recordMoving, recordNewCreases, recordStationary, recordStep, renderRunReport, runRefusal)
import Senbazuru.Sequence.Run
import Senbazuru.Sequence.Syntax (Amount (..), Compass (..), Corner (..), Header (..), Layers (..), Line (..), Move (..), Name (..), PageAxis (..), Point (..), RefusalKind (..), Sense (..), Sequence (..), Side (..), Span (..))
import Senbazuru.Sequence.Write (noFileHeader, writeSequence)
import Test.Hspec
import Test.SequenceExamples (blintz, quarterFold)

spec :: Spec
spec = do
  starting
  running
  quartered
  stopping
  blocked
  pointingElsewhere
  creasing
  precreasing

running :: Spec
running = describe "running a sequence" $ do
  blintzFile <- runIO (loadFoldFile "examples/blintz-base.fold" >>= right)
  let sheets = M.singleton "examples/blintz-base.fold" blintzFile
      runOn sequence' = checkSequence sequence' >>= runSequence defaultRunSettings sheets . elaborate
      oneStep moves = sequenceOf (header "t" (sheetFile "examples/blintz-base.fold") (Just centre)) (step_ "s" moves)
  records <- runIO (right (runRecords <$> runOn blintz))

  it "runs the blintz to five records, one a step, its corners about edges 8 to 11" $ do
    map recordStep records `shouldBe` [1 .. 5]
    map (concatMap snd . recordHinge) records `shouldBe` [[EdgeId 8], [EdgeId 9], [EdgeId 10], [EdgeId 11], [EdgeId 8]]

  -- E2: every record's evidence is a turn checked over its whole path, and
  -- the check found it clear.
  it "checks every turn over its whole path, and finds each clear" $
    forM_ records $ \record -> case recordEvidence record of
      SweptHinge turn -> sweepOutcome (flapCheck turn) `shouldBe` SweepClear

  -- Behind is away from the reader: with the coloured side up, -180, the
  -- recipe's travel; the unfold takes edge 8 back to 0. Turns red if the
  -- reader's side were read backwards, or a move changed another crease.
  it "turns each corner behind by 180, and the unfold back to flat" $
    forM_ (zip3 records [8, 9, 10, 11, 8] [-180, -180, -180, -180, 180]) $ \(record, e, travel) -> do
      let (anglesBefore, anglesAfter) = recordAngles record
      [i | (i, a, b) <- zip3 [0 :: Int ..] anglesBefore anglesAfter, a /= b] `shouldBe` [e]
      (anglesAfter !! e) - (anglesBefore !! e) `shouldBe` travel

  -- E3, as the records show it: each move starts where the last one ended,
  -- and the centre square, the anchor's face, never moves.
  it "hands each move's paper to the next, the anchor's face held still" $ do
    forM_ (zip records (drop 1 records)) $ \(record, next) -> do
      endPoints <- right (frameVertices (surfaceFrame (recordAfter record)))
      startPoints <- right (frameVertices (surfaceFrame (recordBefore next)))
      and (zipWith (\p q -> p == q || maximum (map abs (zipWith (-) (coords p) (coords q))) < 1e-12) endPoints startPoints) `shouldBe` True
    map recordStationary records `shouldBe` replicate 5 (FaceId 0)

  -- The white side up puts the reader's side at -z, so behind is +z: the
  -- same mountain turns the crease the other way.
  it "reads valley and mountain from the reader's side" $ do
    let coloured = sequenceOf (header "t" (sheetFile "examples/blintz-base.fold") (Just centre)) (step_ "s" (fold mountain (cornerOf SouthEast `onto` centre)))
        whiteUp = coloured {seqHeader = (seqHeader coloured) {hSide = WhiteUp}}
    run <- right (runOn whiteUp)
    case runRecords run of
      [record] -> (snd (recordAngles record) !! 8) `shouldBe` 180
      other -> expectationFailure ("expected one record, got " <> show (length other))

  -- moving P picks the paper for a line that does not say which side moves.
  it "folds the side named by moving P, and refuses a line with none" $ do
    let alongEdge8 = Segment (MidpointOfEdge South) (MidpointOfEdge East)
    run <- right (runOn (oneStep (move (Fold MountainFold ToFlat alongEdge8 FlapOfFirstArgument (Just (CornerOf SouthEast))))))
    map (concatMap snd . recordHinge) (runRecords run) `shouldBe` [[EdgeId 8]]
    refusal (runOn (oneStep (fold mountain alongEdge8))) `shouldBe` Just (Selecting SeedMissing)

  describe "refuses" $ do
    it "a sheet it was not given" $
      case checkSequence blintz >>= runSequence defaultRunSettings M.empty . elaborate of
        Left (SheetRefused _ "examples/blintz-base.fold" SheetNotLoaded) -> pure ()
        other -> expectationFailure ("expected the sheet refused, got " <> show (fmap (length . runRecords) other))

    -- An anchor inside corner south-east's triangle moves with it.
    it "a fold that would carry the anchor's paper, until re-anchoring is run" $ do
      let carried = sequenceOf (header "t" (sheetFile "examples/blintz-base.fold") (Just (at (19 / 20) (1 / 50)))) (step_ "s" (fold mountain (cornerOf SouthEast `onto` centre)))
      case refusal (runOn carried) of
        Just (MoveNotRunYet _) -> pure ()
        other -> expectationFailure ("expected re-anchoring to be not run yet, got " <> show other)

    -- c1 folds the corner behind, is unfolded, and the corner is then folded
    -- in front: edge 8 is no longer where c1 left it, so unfolding c1 again
    -- would undo the later fold. A second unfold of a flat crease is skipped.
    it "an unfold of a crease folded again since, and skips one lying flat" $ do
      let later = sequenceOf (header "t" (sheetFile "examples/blintz-base.fold") (Just centre)) $ do
            c1 <- step "c1" "a" (fold mountain (cornerOf SouthEast `onto` centre))
            step_ "b" (unfold [c1])
            step_ "c" (unfold [c1])
            step_ "d" (fold valley (cornerOf SouthEast `onto` centre))
            step_ "e" (unfold [c1])
      refusal (runOn later) `shouldBe` Just (UnfoldChangedSince (EdgeId 8))
      let twice = sequenceOf (header "t" (sheetFile "examples/blintz-base.fold") (Just centre)) $ do
            c1 <- step "c1" "a" (fold mountain (cornerOf SouthEast `onto` centre))
            step_ "b" (unfold [c1])
            step_ "c" (unfold [c1])
      fmap (length . runRecords) (runOn twice) `shouldBe` Right 2

    -- Edge south onto the line up the middle: the lines cross at (1/2, 0),
    -- the middle of edge south, so whichever crease is chosen, edge south
    -- lies across it and does not say which side moves.
    it "a line laid onto a line, when the first lies across the fold" $
      case refusal (runOn (oneStep (fold behind (LineOnto (edge South) (Segment (MidpointOfEdge South) (MidpointOfEdge North)) (Just (MidpointOfEdge East)))))) of
        Just (Selecting (SegmentStraddles a b)) -> sortOn coords2 [a, b] `shouldSatisfy` (\ends -> and (zipWith close ends [V2 0 0, V2 1 0]) && length ends == 2)
        other -> expectationFailure ("expected edge south refused as lying across the fold, got " <> show other)

    it "a move it does not make yet, by name" $
      refusal (runOn (oneStep (turnOver LeftRight))) `shouldBe` Just (MoveNotRunYet "\"turn over\"")
  where
    coords (V3 x y z) = [x, y, z]
    coords2 (V2 x y) = [x, y]
    close (V2 x y) (V2 x' y') = abs (x - x') < 1e-12 && abs (y - y') < 1e-12
    refusal = \case
      Left (StepRefused _ _ _ failure) -> Just failure
      _ -> Nothing

-- The quarter fold, PRD 09's test 1: each fold lays one side of the sheet
-- onto the opposite side, L1 to L2, about creases the sheet has. The fixture
-- holds the states its author folded by hand, so the run's angles have
-- something independent to equal.
quartered :: Spec
quartered = describe "the quarter fold" $ do
  sheet <- runIO (loadFoldFile "examples/quarter-fold-steps.fold" >>= right)
  records <- runIO (right (runRecords <$> (checkSequence quarterFold >>= runSequence defaultRunSettings (M.singleton "examples/quarter-fold-steps.fold" sheet) . elaborate)))

  it "folds in half about edges 8 and 10, then in quarters about 9 and 11" $
    map (sort . concatMap snd . recordHinge) records `shouldBe` [[EdgeId 8, EdgeId 10], [EdgeId 9, EdgeId 11]]

  -- The second fold, one valley fold, writes edge 9 at +180 and edge 11 at
  -- -180: both faces beside edge 11 were turned over by the first (PRD
  -- decisions D5, "the line that looks like a typo").
  it "ends each fold at the angles the fixture's author wrote" $
    map (snd . recordAngles) records `shouldBe` map edgesFoldAngle (otherFrames sheet)

  -- PRD 02 §6.3: the seed is the vertex mean of the face beside the first
  -- line's longest piece, ties to the lowest, then the leftmost. Edge west's
  -- lower half for the first fold; edge north's west half, (1/4, 3/4), for
  -- the second, as §6.3 works it.
  it "keeps as each seed the face beside the first side's lowest, then leftmost, piece" $
    map (map fst . recordMoving) records `shouldBe` [[MaterialPoint (V2 0.25 0.25)], [MaterialPoint (V2 0.25 0.75)]]

-- A run that reaches not modelled stops there and still succeeds, keeping
-- every move made before it, so that the states up to the gap can be
-- written and drawn (PRDs/decisions.md, D21; PRD 04's A18).
stopping :: Spec
stopping = describe "a run that reaches not modelled" $ do
  sheet <- runIO (loadFoldFile "examples/quarter-fold-steps.fold" >>= right)
  let runOn sequence' = checkSequence sequence' >>= runSequence defaultRunSettings (M.singleton "examples/quarter-fold-steps.fold" sheet) . elaborate
      -- The quarter fold, its second step's moves given, and then its second
      -- fold, which would leave a record of step 3 if a run went on past a
      -- stop at step 2.
      quarterWith second = sequenceOf (header "A square folded into quarters" (sheetFile "examples/quarter-fold-steps.fold") (Just (at (3 / 4) (1 / 4)))) $ do
        _ <- step "half" "Fold the left half behind, onto the right." (fold behind (LineOnto (edge West) (edge East) Nothing))
        _ <- step "quarter" "Fold the top half down in front, onto the bottom." second
        step_ "Fold the top half down in front, onto the bottom." (fold inFront (LineOnto (edge North) (edge South) Nothing))
      quarterStop = RunStop 2 (Just (Name "quarter")) (Just "Fold the top half down in front, onto the bottom.") NoSpan "fold in quarters"

  it "stops at its step, keeping the moves before it and running none after (A18)" $ do
    run <- right (runOn (quarterWith (notModelled "fold in quarters")))
    map recordStep (runRecords run) `shouldBe` [1]
    runStop run `shouldBe` Just quarterStop
    runRefusal run `shouldBe` Just (StepRefused 2 (Just (Name "quarter")) NoSpan (NotModelledStop "fold in quarters"))
    fmap explain (runRefusal run) `shouldSatisfy` maybe False (T.isPrefixOf "step 2 (quarter): \"fold in quarters\" is not modelled")

  -- Stopped before any move, the run has no record, and still succeeds.
  it "stops at the first step with no record made" $ do
    run <- right (runOn (sequenceOf (header "Not yet" (sheetFile "examples/quarter-fold-steps.fold") (Just (at (3 / 4) (1 / 4)))) (step_ "Squash it." (notModelled "squash fold"))))
    runRecords run `shouldBe` []
    runStop run `shouldBe` Just (RunStop 1 Nothing (Just "Squash it.") NoSpan "squash fold")

  it "keeps a move its own step made before the stop" $ do
    run <- right (runOn (quarterWith (fold inFront (LineOnto (edge North) (edge South) Nothing) >> notModelled "squash the corner")))
    map recordStep (runRecords run) `shouldBe` [1, 2]
    fmap stopText (runStop run) `shouldBe` Just "squash the corner"

  -- not modelled names no paper, so no kind matches it, and the expectation
  -- passes it on: the run stops there just the same.
  it "stops inside expect refused too, which cannot name it" $ do
    run <- right (runOn (quarterWith (expectRefused (RefusalKind "FlapCollision") (NotModelled "fold in quarters"))))
    runStop run `shouldBe` Just quarterStop
    runExpected run `shouldBe` []

  it "has no stop and nothing to refuse when it runs to the end" $ do
    run <- right (runOn quarterFold)
    (runStop run, runRefusal run) `shouldBe` (Nothing, Nothing)

-- A nearest P the rules did not need, pointing at the other answer (owner
-- decision 41). On the blintz sheet, the stretch of edge south west of its
-- midpoint, laid onto the vertical midline's lower half, has two answers,
-- both creases the sheet has: x + y = 1/2 lays the stretch onto that half,
-- and x - y = 1/2 onto the line below the paper, so the first is taken.
-- Midpoint of edge east lies on the second. A run resolves the fold line
-- before it chooses the paper that moves, so the refusal reaches the run,
-- and an author can expect it.
pointingElsewhere :: Spec
pointingElsewhere = describe "a nearest P pointing away from the answer taken" $ do
  sheet <- runIO (loadFoldFile "examples/blintz-base.fold" >>= right)
  let runOn sequence' = checkSequence sequence' >>= runSequence defaultRunSettings (M.singleton "examples/blintz-base.fold" sheet) . elaborate
      stretchOntoHalf = LineOnto (Segment (CornerOf SouthWest) (MidpointOfEdge South)) (Segment (MidpointOfEdge South) Centre) (Just (MidpointOfEdge East))
      foldOnto wrap =
        sequenceOf (header "Onto the midline" (sheetFile "examples/blintz-base.fold") (Just Centre)) $
          step_ "Lay the stretch on the midline." (move (wrap (Fold MountainFold ToFlat stretchOntoHalf FlapOfFirstArgument Nothing)))

  it "is refused as NearestDisagrees at step 1" $
    case runOn (foldOnto id) of
      Left err@(ResolveRefused (InStep 1 Nothing) _ _ (NearestDisagrees pointAt _ _ _)) -> do
        pointAt `shouldBe` V2 1 0.5
        refusalKindOf err `shouldBe` Just (RefusalKind "NearestDisagrees")
      other -> expectationFailure ("expected nearest refused at step 1, got " <> either (show . explain) (show . length . runRecords) other)

  it "and runs, with the outcome kept, when the sequence expects it" $ do
    run <- right (runOn (foldOnto (ExpectRefused (RefusalKind "NearestDisagrees"))))
    runRecords run `shouldBe` []
    runExpected run `shouldBe` [ExpectedRefusal 1 1 (RefusalKind "NearestDisagrees")]

-- A pre-crease (#496, owner decision 14): the paper folded along a line,
-- checked over the whole path, and laid flat again, in one move and one
-- record of kind Precrease. The crease it leaves has no direction, U, since a
-- later move may fold it either way; a crease the paper had keeps its letter,
-- since a pre-crease changes nothing but its new crease (PRD 02 §6.4).
precreasing :: Spec
precreasing = describe "a pre-crease" $ do
  blintzSheet <- runIO (loadFoldFile "examples/blintz-base.fold" >>= right)
  let runOn sheets sequence' = checkSequence sequence' >>= runSequence defaultRunSettings sheets . elaborate
      onSquare = runOn M.empty . sequenceOf (header "A square" sheetSquare Nothing)
      onBlintz = runOn (M.singleton "examples/blintz-base.fold" blintzSheet) . sequenceOf (header "A blintz" (sheetFile "examples/blintz-base.fold") (Just Centre))
      diagonals =
        step "diagonals" "Crease both diagonals." $ do
          move (FoldAndUnfold ValleyFold (Segment (CornerOf SouthWest) (CornerOf NorthEast)) FlapOfFirstArgument (Just (CornerOf SouthEast)))
          move (FoldAndUnfold ValleyFold (Segment (CornerOf SouthEast) (CornerOf NorthWest)) FlapOfFirstArgument (Just (CornerOf SouthWest)))

  -- The crane's first step, on a plain square: two records, each a
  -- pre-crease ending where it began, each leaving its crease U at 0. Turns
  -- red if the paper were left folded, the crease lettered by the sense, or
  -- the record kept the fold's end.
  it "creases the crane's diagonals on a plain square, in two records that end where they began" $ do
    run <- right (onSquare (void diagonals))
    let records = runRecords run
    map recordKind records `shouldBe` [Precrease, Precrease]
    forM_ records $ \record -> do
      began <- right (frameVertices (surfaceFrame (recordBefore record)))
      ended <- right (frameVertices (surfaceFrame (recordAfter record)))
      ended `shouldBe` began
      snd (recordAngles record) `shouldSatisfy` all (== 0)
      [letter | (_, _, letter) <- recordNewCreases record] `shouldBe` [Unassigned]
    renderRunReport run `shouldContain` ["  laid flat again: the paper ends where it began"]

  -- On the blintz, corner south-east's crease is one the sheet has, a
  -- mountain. Pre-creasing along it draws nothing new and leaves it a
  -- mountain at 0. Turns red if a pre-crease made an existing crease U.
  it "draws no crease along one the paper has, and leaves that crease's letter" $ do
    run <- right (onBlintz (step_ "Pre-crease the corner." (move (FoldAndUnfold ValleyFold (Onto (CornerOf SouthEast) Centre) FlapOfFirstArgument Nothing))))
    record <- case runRecords run of
      [r] -> pure r
      other -> fail ("expected one record, got " <> show (length other))
    recordKind record `shouldBe` Precrease
    recordNewCreases record `shouldBe` []
    let edges' = concatMap snd (recordHinge record)
        letters = edgesAssignment (surfaceFrame (recordAfter record))
    [l | EdgeId e <- edges', l <- take 1 (drop e letters)] `shouldBe` [Mountain]
    snd (recordAngles record) `shouldSatisfy` all (== 0)

  -- A pre-crease is checked as its fold is, so what refuses the fold
  -- refuses it, as the same kind. Moving the centre along the diagonal
  -- through it names paper on the new crease, in no one face. Turns red if a
  -- pre-crease skipped the fold's checks, or were refused another way.
  it "is refused by the same kind as its fold" $ do
    let onTheLine moveOf = onBlintz (step_ "Fold along the diagonal." (move (moveOf (Segment (CornerOf SouthWest) (CornerOf NorthEast)) FlapOfFirstArgument (Just Centre))))
        kindOf = either refusalKindOf (const Nothing)
    kindOf (onTheLine (FoldAndUnfold ValleyFold)) `shouldBe` Just (RefusalKind "NotInOneFace")
    kindOf (onTheLine (FoldAndUnfold ValleyFold)) `shouldBe` kindOf (onTheLine (Fold ValleyFold ToFlat))

  -- Its crease is one to fold along later, and its unfold has nothing to
  -- turn while the crease lies flat. Turns red if hinge of could not find
  -- a pre-crease's crease, or an unfold of one made a record.
  it "leaves a crease to fold along later, and an unfold with nothing to do" $ do
    run <- right . onSquare $ do
      p1 <- step "p1" "Crease the horizontal midline." (move (FoldAndUnfold ValleyFold (LineOnto (EdgeOf South) (EdgeOf North) Nothing) FlapOfFirstArgument Nothing))
      step_ "Unfold it, which does nothing." (unfold [p1])
      step_ "Fold the bottom half up along it." (move (Fold ValleyFold ToFlat (hingeOf p1) FlapOfFirstArgument (Just (CornerOf SouthEast))))
    map recordKind (runRecords run) `shouldBe` [Precrease, Turn]
    case runRecords run of
      [made, folded] -> do
        sort (concatMap snd (recordHinge folded)) `shouldBe` sort (concatMap snd (recordHinge made))
        [a | EdgeId e <- concatMap snd (recordHinge folded), a <- take 1 (drop e (snd (recordAngles folded)))] `shouldSatisfy` all (== 180)
      other -> expectationFailure ("expected two records, got " <> show (length other))

-- A fold along a line where no crease runs (#495). On the flat sheet, every
-- crease at rest, the runner creases each face the line crosses and then
-- turns about the new crease, with any the line found already there. The
-- crease's letter is the fold's sense seen from the coloured side.
creasing :: Spec
creasing = describe "a fold along a line where no crease runs" $ do
  let runOn sheets sequence' = checkSequence sequence' >>= runSequence defaultRunSettings sheets . elaborate
      onSquare anchorAt side = runOn M.empty . sequenceOf ((header "A square" sheetSquare anchorAt) {hSide = side})
      corner = CornerOf
      ends (MaterialSegment (MaterialPoint a) (MaterialPoint b), edges, letter) = ([a, b], edges, letter)
      unordered (pair, edges, letter) = (sort' pair, edges, letter)
      sort' = sortOn (\(V2 x y) -> (x, y))
      -- The square folded along one diagonal, unfolded, then along the
      -- other, unfolded again; then whatever comes after.
      bothDiagonals after' = onSquare (Just (at (3 / 4) (1 / 8))) ColouredUp $ do
        c1 <- step "c1" "Fold the top-left corner onto the bottom-right." (fold valley (Onto (corner NorthWest) (corner SouthEast)))
        step_ "Unfold it." (unfold [c1])
        c2 <- step "c2" "Fold the top-right corner onto the bottom-left." (fold valley (Onto (corner NorthEast) (corner SouthWest)))
        step_ "Unfold it." (unfold [c2])
        after' c1
      -- The square folded along its diagonal and unfolded, then along its
      -- vertical midline, which cuts the south and north sides and so
      -- renumbers the diagonal: its crease, edge 4 when it was made, is
      -- edges 6 and 7 after. Then whatever comes after.
      diagonalThenMidline after' = onSquare (Just (at (3 / 4) (1 / 8))) ColouredUp $ do
        c1 <- step "c1" "Fold the top-left corner onto the bottom-right." (fold valley (Onto (corner NorthWest) (corner SouthEast)))
        step_ "Unfold it." (unfold [c1])
        c2 <- step "c2" "Fold the left half onto the right." (fold valley (LineOnto (edge West) (edge East) Nothing))
        step_ "Unfold it." (unfold [c2])
        after' c1

  -- The issue's own test: a plain square folded along a diagonal runs to one
  -- record, whose hinge is the new crease, a valley at 180 once turned, with
  -- the corner on the moving side landed on the opposite corner. Turns red if
  -- the line were refused as needing a crease, or the crease drawn already
  -- folded.
  it "creases a plain square along a diagonal and turns about it, in one record" $ do
    run <- right (onSquare (Just (at (3 / 4) (1 / 4))) ColouredUp (step_ "Fold the top-left corner onto the bottom-right." (fold valley (Onto (corner NorthWest) (corner SouthEast)))))
    record <- one (runRecords run)
    map ends (recordNewCreases record) `shouldBe` [([V2 0 0, V2 1 1], [EdgeId 4], Valley)]
    concatMap snd (recordHinge record) `shouldBe` [EdgeId 4]
    drop 4 (fst (recordAngles record)) `shouldBe` [0]
    drop 4 (snd (recordAngles record)) `shouldBe` [180]
    landed <- right (frameVertices (surfaceFrame (recordAfter record)))
    case drop 3 landed of
      V3 x y z : _ -> maximum (map abs [x - 1, y, z]) `shouldSatisfy` (< 1e-12)
      [] -> expectationFailure "the square has no corner north-west"
    renderRunReport run `shouldContain` ["  new crease: (0, 0) to (1, 1), valley (internal edge 4)"]
    void (writeSequence noFileHeader run) `shouldBe` Right ()

  -- On a sheet two units across, the report gives the new crease in sheet
  -- lengths, as it gives the line: (0, 0) to (1, 1), not to (2, 2). Turns
  -- red if the crease were printed in the file's own units.
  it "reports the new crease in sheet lengths, as it reports the line" $ do
    let double = squareSheet {keyFrame = (keyFrame squareSheet) {verticesCoords = [[0, 0], [2, 0], [2, 2], [0, 2]]}}
    run <- right (runOn (M.singleton "double.fold" double) (sequenceOf (header "A larger square" (sheetFile "double.fold") (Just (at (3 / 4) (1 / 4)))) (step_ "Fold the top-left corner onto the bottom-right." (fold valley (Onto (corner NorthWest) (corner SouthEast))))))
    renderRunReport run `shouldContain` ["  line corner north-west to corner south-east: through (0.5, 0.5), along (0.707107, 0.707107)"]
    renderRunReport run `shouldContain` ["  new crease: (0, 0) to (1, 1), valley (internal edge 4)"]

  -- The square's default anchor is its centre, on the diagonal. Folding
  -- corner south-east up onto corner north-west turns the lower triangle,
  -- so the anchor moves to the upper one's vertex mean, (1/3, 2/3), and the
  -- record says so (decisions C19). The upper triangle is the higher of the
  -- two, so the rule that breaks ties, lowest first, would pick the turning
  -- one: turns red if the anchor's new face ignored what the move turns, or
  -- the anchor stayed on the crease.
  it "moves an anchor the new crease runs through to the face the fold holds still" $ do
    run <- right (onSquare Nothing ColouredUp (step_ "Fold the bottom-right corner onto the top-left." (fold valley (Onto (corner SouthEast) (corner NorthWest)))))
    record <- one (runRecords run)
    case recordAnchor record of
      (MaterialPoint was, MaterialPoint now) -> do
        was `shouldBe` V2 0.5 0.5
        norm (now ^-^ V2 (1 / 3) (2 / 3)) `shouldSatisfy` (< 1e-12)
    landed <- right (frameVertices (surfaceFrame (recordAfter record)))
    case drop 1 landed of
      V3 x y z : _ -> maximum (map abs [x, y - 1, z]) `shouldSatisfy` (< 1e-12)
      [] -> expectationFailure "the square has no corner south-east"
    renderRunReport run `shouldContain` ["  anchor moved: (0.5, 0.5) to (0.333333, 0.666667), off the new crease"]

  -- On the blintz, anchored at its centre, the diagonal crosses the central
  -- square through the anchor. Folding the south-east corner over turns the
  -- square's south-east half, so the anchor moves to the vertex mean of its
  -- north-west half, (0, 1/2), (1/4, 1/4), (3/4, 3/4), (1/2, 1).
  it "moves the blintz's anchor off a diagonal through its centre" $ do
    blintzSheet <- loadFoldFile "examples/blintz-base.fold" >>= right
    run <- right (runOn (M.singleton "examples/blintz-base.fold" blintzSheet) (sequenceOf (header "t" (sheetFile "examples/blintz-base.fold") (Just Centre)) (step_ "Fold the bottom-right corner over." (move (Fold ValleyFold ToFlat (Segment (corner SouthWest) (corner NorthEast)) FlapOfFirstArgument (Just (corner SouthEast)))))))
    record <- one (runRecords run)
    case recordAnchor record of
      (MaterialPoint was, MaterialPoint now) -> do
        was `shouldBe` V2 0.5 0.5
        norm (now ^-^ V2 0.375 0.625) `shouldSatisfy` (< 1e-12)

  -- White side up, a valley towards the reader is a mountain from the
  -- coloured side, which is the side FOLD's letters are read from. Turns red
  -- if the letter were the author's sense as written.
  it "letters the crease from the coloured side, a mountain with the white side up" $ do
    run <- right (onSquare (Just (at (3 / 4) (1 / 4))) WhiteUp (step_ "Fold the top-left corner onto the bottom-right." (fold valley (Onto (corner NorthWest) (corner SouthEast)))))
    record <- one (runRecords run)
    [letter | (_, _, letter) <- recordNewCreases record] `shouldBe` [Mountain]
    drop 4 (snd (recordAngles record)) `shouldBe` [-180]

  -- The second diagonal crosses the first's crease at the centre: two faces
  -- crossed, two stretches meeting there, one new crease cut in two by the
  -- old. Turns red if the stretches were kept apart, or the old crease were
  -- creased again.
  it "makes one crease of the stretches that meet across an old crease" $ do
    run <- right (bothDiagonals (const (pure ())))
    case [r | r <- runRecords run, recordStep r == 3] of
      [record] -> do
        map (unordered . ends) (recordNewCreases record) `shouldBe` [([V2 0 1, V2 1 0], [EdgeId 6, EdgeId 7], Valley)]
        sort (concatMap snd (recordHinge record)) `shouldBe` [EdgeId 6, EdgeId 7]
      other -> expectationFailure ("expected one record at step 3, got " <> show (length other))

  -- A sheet with a crease up the middle and one from the west edge to it,
  -- folded along the line through both halves: the west half runs along the
  -- crease the sheet has, the east half crosses paper with none. Only the
  -- east half is creased, and the fold turns about both. Turns red if the
  -- whole line were creased again, or the old half left out of the hinge.
  it "creases only where the line has no crease, and turns about both" $ do
    let sheet =
          squareSheet
            { keyFrame =
                (keyFrame squareSheet)
                  { verticesCoords = verticesCoords (keyFrame squareSheet) ++ [[0.5, 0], [0.5, 1], [0, 0.5], [0.5, 0.5]],
                    edgesVertices = edgesVertices (keyFrame squareSheet) ++ [(VertexId 4, VertexId 5), (VertexId 6, VertexId 7)],
                    edgesAssignment = edgesAssignment (keyFrame squareSheet) ++ [Valley, Valley],
                    edgesFoldAngle = replicate 6 0,
                    facesVertices = []
                  }
            }
    run <- right (runOn (M.singleton "half.fold" sheet) (sequenceOf (header "Half creased" (sheetFile "half.fold") (Just (at (3 / 4) (3 / 4)))) (step_ "Fold the bottom half up." (fold valley (LineOnto (edge South) (edge North) Nothing)))))
    record <- one (runRecords run)
    case recordNewCreases record of
      [made@(_, ids, Valley)] -> do
        fst3 (unordered (ends made)) `shouldBe` [V2 0.5 0.5, V2 1 0.5]
        let hinge = concatMap snd (recordHinge record)
            (_, after') = recordAngles record
        length hinge `shouldSatisfy` (> length ids)
        all (`elem` hinge) ids `shouldBe` True
        [take 1 (drop e after') | EdgeId e <- hinge] `shouldBe` replicate (length hinge) [180]
      other -> expectationFailure ("expected one new valley, got " <> show other)

  -- Creasing through the layers of folded paper is M4's. Turns red if the
  -- runner creased one layer of a folded model as though it were the sheet.
  it "refuses a new crease on folded paper" $
    case onSquare (Just (at (3 / 4) (1 / 8))) ColouredUp $ do
      step_ "Fold the top-left corner onto the bottom-right." (fold valley (Onto (corner NorthWest) (corner SouthEast)))
      step_ "Fold the top-right corner to the centre." (fold valley (Onto (corner NorthEast) Centre)) of
      Left (ResolveRefused (InStep 2 Nothing) _ _ (NotRunYet what)) -> what `shouldSatisfy` T.isInfixOf "folded paper"
      other -> expectationFailure ("expected a new crease on folded paper refused, got " <> either (show . explain) (const "a run") other)

  -- Once a later move has creased the paper, an earlier record's edge ids
  -- name other edges: the midline cut the diagonal's crease in two at the
  -- centre, and cut two sides before it, so edge 4 then is edges 6 and 7
  -- now. Folding along "hinge of c1" finds both pieces by where they lie,
  -- and folds corner north-west onto corner south-east again. Turns red if
  -- the record's ids were read as they stand.
  it "finds a move's crease again on paper creased since, for hinge of" $ do
    run <- right (diagonalThenMidline (\c1 -> step_ "Fold the first again." (move (Fold ValleyFold ToFlat (hingeOf c1) FlapOfFirstArgument (Just (corner NorthWest))))))
    case [r | r <- runRecords run, recordStep r == 5] of
      [record] -> do
        sort (concatMap snd (recordHinge record)) `shouldBe` [EdgeId 6, EdgeId 7]
        [a | e <- [6, 7], a <- take 1 (drop e (snd (recordAngles record)))] `shouldBe` [180, 180]
        landed <- right (frameVertices (surfaceFrame (recordAfter record)))
        case drop 3 landed of
          V3 x y z : _ -> maximum (map abs [x - 1, y, z]) `shouldSatisfy` (< 1e-12)
          [] -> expectationFailure "the square has no corner north-west"
      other -> expectationFailure ("expected one record at step 5, got " <> show (length other))

  -- And unfold c1, once that fold has turned its pieces again, turns them
  -- back on the side c1's paper moved: the moving side is read from which
  -- way the faces run along the crease, since the faces were traced afresh.
  -- Turns red if the side were looked up by c1's face ids, or the paper
  -- landed anywhere but where it began.
  it "turns a move's crease back on paper creased since, for unfold" $ do
    run <- right (diagonalThenMidline (\c1 -> step_ "Fold the first again." (move (Fold ValleyFold ToFlat (hingeOf c1) FlapOfFirstArgument (Just (corner NorthWest)))) >> step_ "Unfold the first." (unfold [c1])))
    case [r | r <- runRecords run, recordStep r == 6] of
      [record] -> do
        sort (concatMap snd (recordHinge record)) `shouldBe` [EdgeId 6, EdgeId 7]
        [a | e <- [6, 7], a <- take 1 (drop e (snd (recordAngles record)))] `shouldBe` [0, 0]
        landed <- right (frameVertices (surfaceFrame (recordAfter record)))
        take 4 landed `shouldSatisfy` all (\(V3 x y z, (u, v)) -> maximum (map abs [x - u, y - v, z]) < 1e-12) . (`zip` [(0, 0), (1, 0), (1, 1), (0, 1)])
      other -> expectationFailure ("expected one record at step 6, got " <> show (length other))

  -- Folded again only to 90, c1's crease is not where c1 left it, and
  -- unfolding c1 would undo that fold too: each piece is compared with the
  -- record's own edge it came from. Turns red if the pieces' angles were
  -- read against the record's numbering.
  it "refuses to unfold a move whose crease changed since, on paper creased since" $
    case diagonalThenMidline (\c1 -> step_ "Fold the first part way." (move (Fold ValleyFold (Degrees 90) (hingeOf c1) FlapOfFirstArgument (Just (corner NorthWest)))) >> step_ "Unfold the first." (unfold [c1])) of
      Left (StepRefused 6 _ _ (UnfoldChangedSince e)) -> e `shouldSatisfy` (`elem` [EdgeId 6, EdgeId 7])
      other -> expectationFailure ("expected the unfold refused as changed since, got " <> either (show . explain) (const "a run") other)
  where
    one = \case
      [record] -> pure record
      records -> fail ("expected one record, got " <> show (length records))
    fst3 (a, _, _) = a

-- A turn blocked part-way. Folding needs paper lying flat, so only an
-- unfold can turn paper with something standing in its way. On the
-- accordion, c1 lays the last strip on the third; the left half is then
-- turned 135 degrees in front, so it leans over them in the air; and
-- unfolding c1 lifts the last strip back up into it. The sweep, which checks
-- the whole path before the turn's ends are judged, refuses it, with a
-- witness a quarter of the way along: a point of contact, not the first.
blocked :: Spec
blocked = describe "a turn blocked part-way" $ do
  accordion <- runIO (loadFoldFile "examples/accordion.fold" >>= right)
  let runWith settings sequence' = checkSequence sequence' >>= runSequence settings (M.singleton "examples/accordion.fold" accordion) . elaborate
      along x seed amount = Fold ValleyFold amount (Segment (at x 0) (at x 1)) FlapOfFirstArgument (Just (CornerOf seed))
      unfoldInto wrap = sequenceOf (header "Into a leaning flap" (sheetFile "examples/accordion.fold") (Just (at (5 / 8) (1 / 2)))) $ do
        c1 <- step "c1" "Lay the last strip on the third, in front." (move (along (3 / 4) SouthEast ToFlat))
        step_ "Lean the left half over them." (move (along (1 / 2) SouthWest (Degrees 135)))
        step_ "Open the last strip again." (move (wrap (Unfold [refName c1])))

  it "is refused as FlapCollision part-way through, at step 3" $
    case runWith defaultRunSettings (unfoldInto id) of
      Left err@(StepRefused 3 _ _ (FlapRefused (FlapCollision t _))) -> do
        t `shouldSatisfy` (\progress -> progress > 0 && progress < 1)
        refusalKindOf err `shouldBe` Just (RefusalKind "FlapCollision")
      other -> expectationFailure ("expected a collision at step 3, got " <> either (show . explain) (show . length . runRecords) other)

  it "and runs, with the outcome kept, when the sequence expects it" $ do
    run <- right (runWith defaultRunSettings (unfoldInto (ExpectRefused (RefusalKind "FlapCollision"))))
    length (runRecords run) `shouldBe` 2
    runExpected run `shouldBe` [ExpectedRefusal 3 1 (RefusalKind "FlapCollision")]

  -- With no depth to subdivide, the sweep can neither clear the turn nor find
  -- the flap in the way: it gives up, and that is a refusal of its own.
  it "is unresolved by a sweep with no depth, and that can be expected too" $ do
    let shallow = defaultRunSettings {runSweep = SweepSettings 0 1}
    case runWith shallow (unfoldInto id) of
      Left err@(StepRefused 3 _ _ (FlapRefused FlapUnresolved {})) -> refusalKindOf err `shouldBe` Just (RefusalKind "FlapUnresolved")
      other -> expectationFailure ("expected the unfold at step 3 unresolved, got " <> either (show . explain) (show . length . runRecords) other)
    run <- right (runWith shallow (unfoldInto (ExpectRefused (RefusalKind "FlapUnresolved"))))
    runExpected run `shouldBe` [ExpectedRefusal 3 1 (RefusalKind "FlapUnresolved")]

starting :: Spec
starting = describe "the state a run starts from" $ do
  -- The fixture records its four corners folded in, at -180. Turns red if a
  -- file angle survives, or if a crease lying flat loses the M it was drawn
  -- with.
  it "lays the blintz flat and keeps its creases mountains" $ do
    state <- start "examples/blintz-base.fold"
    let frame = workingPattern state
    edgesFoldAngle frame `shouldBe` replicate (length (edgesVertices frame)) 0
    [edgesAssignment frame !! e | e <- [8 .. 11]] `shouldBe` replicate 4 Mountain
    faceOrders frame `shouldBe` []
    length (facesVertices frame) `shouldBe` 5

  -- The central square is largest, and its vertex mean is the centre, which
  -- is where `anchor centre` puts it too. Turns red if the anchor's face were
  -- not put first: folding holds its first face still.
  it "anchors the blintz at the centre of its central square, put first" $ do
    state <- start "examples/blintz-base.fold"
    stateAnchor state `shouldBe` MaterialPoint (V2 0.5 0.5)
    firstMean <- faceMean (workingPattern state) 0
    firstMean `shouldBe` V2 0.5 0.5

  -- All four faces tie on area; faces 0 and 3 tie on height, and face 3 is
  -- further left. Turns red if ties went by face id or by the highest mean.
  it "breaks a tie on area by the lowest and then the leftmost vertex mean" $ do
    state <- start "examples/quarter-fold-steps.fold"
    stateAnchor state `shouldBe` MaterialPoint (V2 0.25 0.25)
    firstMean <- faceMean (workingPattern state) 0
    firstMean `shouldBe` V2 0.25 0.25

  -- A sheet halved at x = 1/2 - 1e-13: the right half is larger by 2e-13, a
  -- difference rounding could make, so the halves tie on area and on height,
  -- and the left half wins as the leftmost. Turns red if areas were compared
  -- exactly, when the right half would win.
  it "treats areas that differ only by rounding as tied" $ do
    let x = 0.5 - 1e-13
        halves =
          emptyFrame
            { verticesCoords = [[0, 0], [x, 0], [1, 0], [1, 1], [x, 1], [0, 1]],
              edgesVertices = [(VertexId a, VertexId b) | (a, b) <- [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 0), (1, 4)]],
              edgesAssignment = replicate 6 Border ++ [Mountain]
            }
    state <- right (sheetState (withKey (const halves) squareSheet))
    case stateAnchor state of
      MaterialPoint (V2 ax _) -> ax `shouldSatisfy` (< 0.5)

  -- crane.fold writes no angles: 58 M, 41 V, 20 F and 10 B. Turns red if any
  -- letter is rewritten, F at 0 included.
  it "keeps every crease's letter as drawn when nothing contradicts it" $ do
    file <- load "examples/crane.fold"
    state <- right (sheetState file)
    edgesAssignment (workingPattern state) `shouldBe` edgesAssignment (keyFrame file)

  -- F means unfolded, so an F at an angle contradicts itself and the angle
  -- is believed. U says only that the direction is undecided, so it stays U
  -- at any angle. Turns red if the angle were trusted over U, or F kept at an
  -- angle.
  it "believes an F crease's angle, and keeps U at any angle" $
    forM_ [(Flat, -90, Mountain), (Flat, 90, Valley), (Flat, 0, Flat), (Flat, 1e-11, Flat), (Unassigned, 45, Unassigned)] $ \(letter, angle, expected) -> do
      state <- right (sheetState (diagonal letter angle))
      let frame = workingPattern state
      [a | ((VertexId 0, VertexId 2), a) <- zip (edgesVertices frame) (edgesAssignment frame)] `shouldBe` [expected]
      edgesFoldAngle frame `shouldBe` replicate 5 0

  -- A face's normal points the way its ring turns, so a clockwise ring would
  -- face the other way from the file's +z.
  it "winds every face anticlockwise on the sheet" $ do
    state <- right (sheetState (squareWith [3, 2, 1, 0]))
    area <- faceArea (workingPattern state) 0
    area `shouldSatisfy` (> 0)
    forM_ ["examples/blintz-base.fold", "examples/crane.fold", "examples/bird-base.fold"] $ \path -> do
      frame <- workingPattern <$> start path
      areas <- mapM (faceArea frame) [0 .. length (facesVertices frame) - 1]
      areas `shouldSatisfy` all (> 0)

  it "starts sheet square as the unit square, anchored at its centre" $ do
    state <- right (sheetState squareSheet)
    length (facesVertices (workingPattern state)) `shouldBe` 1
    edgesAssignment (workingPattern state) `shouldBe` replicate 4 Border
    stateAnchor state `shouldBe` MaterialPoint (V2 0.5 0.5)

  describe "refuses a sheet that is not paper before folding" $ do
    -- The file keeps its paper in sixteen folded states, not a key frame.
    it "with an empty key frame, naming the file's frames" $ do
      file <- load "examples/bird-base-sequence.fold"
      sheetState file `shouldBe` Left (SheetHasNoVertices 16)
      explain (SheetRefused NoSpan "examples/bird-base-sequence.fold" (SheetHasNoVertices 16))
        `shouldSatisfy` T.isPrefixOf "sheet \"examples/bird-base-sequence.fold\": its key frame has no vertices; the file keeps its paper in 16 file_frames"

    it "already folded, by its relief or by its class" $ do
      file <- load "examples/simple.fold"
      case sheetState file of
        Left (SheetAlreadyFolded (ByRelief z)) -> z `shouldSatisfy` (> 0)
        other -> expectationFailure ("expected a relief refusal, got " <> show other)
      sheetState (withKey (\f -> f {frameClasses = ["foldedForm"]}) squareSheet) `shouldBe` Left (SheetAlreadyFolded ByClass)

    -- An L whose arms are a tenth wide: its corners average to a point in
    -- the empty quarter. Turns red if the anchor were taken without asking
    -- whether it lies on paper.
    it "whose default anchor falls outside its only face" $ do
      let l = [[0, 0], [1, 0], [1, 0.1], [0.1, 0.1], [0.1, 1], [0, 1]]
          frame = emptyFrame {verticesCoords = l, edgesVertices = [(VertexId i, VertexId ((i + 1) `mod` 6)) | i <- [0 .. 5]], edgesAssignment = replicate 6 Border, facesVertices = [map VertexId [0 .. 5]]}
      case sheetState (withKey (const frame) squareSheet) of
        Left (DefaultAnchorOutside (V2 x y)) -> (x, y) `shouldSatisfy` (\(a, b) -> abs (a - 2.2 / 6) < 1e-12 && abs (b - 2.2 / 6) < 1e-12)
        other -> expectationFailure ("expected the anchor refused, got " <> show other)

    -- The same question on a face that is not convex but whose mean is on
    -- paper: a thick arm three long and a short one, the mean (7/6, 2/5) in
    -- the long arm. Turns red if a convex-only test were used, which calls the
    -- mean outside because it lies beyond the line of the short arm's inner
    -- side.
    it "but not a mean that lies on paper in a face that is not convex" $ do
      let l = [[0, 0], [3, 0], [3, 0.5], [0.5, 0.5], [0.5, 0.7], [0, 0.7]]
          frame = emptyFrame {verticesCoords = l, edgesVertices = [(VertexId i, VertexId ((i + 1) `mod` 6)) | i <- [0 .. 5]], edgesAssignment = replicate 6 Border, facesVertices = [map VertexId [0 .. 5]]}
      state <- right (sheetState (withKey (const frame) squareSheet))
      case stateAnchor state of
        MaterialPoint (V2 x y) -> (x, y) `shouldSatisfy` (\(a, b) -> abs (a - 7 / 6) < 1e-12 && abs (b - 0.4) < 1e-12)
  where
    load path = loadFoldFile path >>= right
    start path = load path >>= right . sheetState
    -- The unit square cut by one crease from corner 0 to corner 2.
    diagonal letter angle =
      withKey
        ( \f ->
            f
              { edgesVertices = edgesVertices f ++ [(VertexId 0, VertexId 2)],
                edgesAssignment = edgesAssignment f ++ [letter],
                edgesFoldAngle = replicate 4 0 ++ [angle],
                facesVertices = []
              }
        )
        squareSheet
    squareWith ring = withKey (\f -> f {facesVertices = [map VertexId ring]}) squareSheet
    withKey change file = file {keyFrame = change (keyFrame file)}

-- | A face's ring on the sheet, from the frame's own vertices.
ringOf :: Frame -> Int -> IO [V2]
ringOf frame face = do
  points <- right (frameVertices frame)
  pure [V2 x y | VertexId i <- facesVertices frame !! face, let V3 x y _ = points !! i]

faceArea :: Frame -> Int -> IO Double
faceArea frame face = signedArea <$> ringOf frame face

faceMean :: Frame -> Int -> IO V2
faceMean frame face = do
  ring <- ringOf frame face
  let n = fromIntegral (length ring)
  pure (V2 (sum [x | V2 x _ <- ring] / n) (sum [y | V2 _ y <- ring] / n))

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
