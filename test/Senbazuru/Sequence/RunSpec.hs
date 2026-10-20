-- | Where a run starts: 'sheetState' on the repository's sheets, and on small
-- sheets made here for the cases no fixture has, such as a crease drawn F at
-- an angle or a face wound clockwise.
module Senbazuru.Sequence.RunSpec (spec) where

import Control.Monad (forM_, void)
import Data.Aeson (object, toJSON, (.=))
import Data.Aeson.KeyMap qualified as KM
import Data.List (sort, sortOn)
import Data.Map.Strict qualified as M
import Data.Maybe (isJust)
import Data.Text qualified as T
import Senbazuru.Explain (explain)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Query (frameVertices)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..), norm, (^-^))
import Senbazuru.Geometry.Polygon (signedArea)
import Senbazuru.Geometry.Rigid (Mat3 (..), applyRigid, identity, matApply, rigidLinear)
import Senbazuru.Geometry.Rigid qualified as Rigid
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Flap (FlapError (..), flapCheck)
import Senbazuru.Origami.HingeSweep (SweepCheck (..), SweepOutcome (..), SweepSettings (..))
import Senbazuru.Origami.Step (motionsBetween, wholeModelMotion)
import Senbazuru.Origami.Surface (SurfaceError (..), surfaceFrame)
import Senbazuru.Sequence.Build
import Senbazuru.Sequence.Check (checkSequence)
import Senbazuru.Sequence.Elaborate (elaborate)
import Senbazuru.Sequence.Error (FoldedBy (..), MoveFailure (..), Place (..), ResolveProblem (..), SelectionError (..), SequenceError (..), SheetProblem (..), refusalKindOf)
import Senbazuru.Sequence.Record (ExpectedRefusal (..), MaterialPoint (..), MaterialSegment (..), MoveKind (..), Presenting (..), ResolvedReference (..), RouteEvidence (..), Run (..), RunStop (..), StepCost (..), WrittenState (..), displayBefore, recordAfter, recordAnchor, recordAngles, recordBefore, recordCost, recordEvidence, recordHinge, recordKind, recordMoving, recordNewCreases, recordPlacement, recordPresentation, recordResolved, recordStationary, recordStep, renderRunReport, runRefusal, writtenStates)
import Senbazuru.Sequence.Run
import Senbazuru.Sequence.Syntax (Amount (..), Compass (..), Corner (..), Header (..), Layers (..), Line (..), Located (..), Move (..), Name (..), PageAxis (..), Point (..), RefusalKind (..), Sense (..), Sequence (..), Side (..), Span (..), Turning (..))
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
  turningOver
  rotating
  reanchoring
  reanchoringOntoStandingPaper

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
      Presented -> expectationFailure "the blintz turns nothing over"
      NoMotion -> expectationFailure "the blintz names no anchor"

  -- E2's second half: what each move cost, as counted work, set from a
  -- reviewed run (decisions C89). Each corner, and the reopening, sweeps its
  -- turn clear as one interval, and folds the pattern afresh 8 times: 3
  -- preparing the turn, 2 checking the layer order at its ends, 2 for the
  -- record's surfaces and 1 for the join check; the fold each move starts
  -- from is the last join check's, kept. Turns red if a refold is added or a
  -- kept fold dropped, or if the sweep needs other intervals.
  it "costs each move the work a reviewed run counted" $
    map ((\cost -> (costSweepIntervals cost, costRefolds cost)) . recordCost) records `shouldBe` [(1, 8), (1, 8), (1, 8), (1, 8), (1, 8)]

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
      refusal (runOn (oneStep (void (mark "m" centre Nothing)))) `shouldBe` Just (MoveNotRunYet "\"mark\"")
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

  -- Each fold's two creases lie on two layers and continue one line on the
  -- sheet, the vertical and then the horizontal midline, so each hinge is one
  -- stretch, unlike the helmet base's, whose creases meet at an angle.
  it "makes each hinge one stretch, its creases continuing one line on the sheet" $
    map (map (sort . snd) . recordHinge) records `shouldBe` [[[EdgeId 8, EdgeId 10]], [[EdgeId 9, EdgeId 11]]]

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
    -- Each creases the square before it turns, and moves the anchor off its
    -- new crease: the default anchor is the centre, on the first diagonal;
    -- it moves to (1/3, 2/3), which is on the second, and then to (1/2, 5/6).
    -- Each is one refold, two more than a blintz move's 8. Turns red if
    -- either went uncounted.
    map recordCost records `shouldBe` [StepCost 1 10, StepCost 1 10]
    [norm (m ^-^ p) < 1e-12 | (record, p) <- zip records [V2 (1 / 3) (2 / 3), V2 0.5 (5 / 6)], let { (_, MaterialPoint m) = recordAnchor record }] `shouldBe` [True, True]

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
        [a | EdgeId e <- concatMap snd (recordHinge folded), a <- take 1 (drop e (snd (recordAngles folded)))] `shouldSatisfy` (\angles -> not (null angles) && all (== 180) angles)
      other -> expectationFailure ("expected two records, got " <> show (length other))

-- A turn-over (#95, decisions D5): the whole model shown from its other side,
-- about an axis through its own middle. No paper moves; the state's
-- presentation changes, and with it the reader's side and the states a run
-- writes.
turningOver :: Spec
turningOver = describe "a turn-over" $ do
  let runOn sequence' = checkSequence sequence' >>= runSequence defaultRunSettings M.empty . elaborate
      onSquare side = runOn . sequenceOf ((header "A square" sheetSquare Nothing) {hSide = side})
      corners frame = [V3 x y z | x : y : rest <- take 4 (verticesCoords frame), let z = case rest of c : _ -> c; [] -> 0]
      near (V3 a b c) (V3 x y z) = maximum (map abs [a - x, b - y, c - z]) < 1e-12

  -- The square turned over left-right: one record, presented, its two
  -- surfaces one, written with corner (0, 0) at (1, 0) and its face showing
  -- its back, so classed a folded form; and the page finds no fold between
  -- the two written states, only a turn of the whole model. The corners land
  -- exactly, since a half turn's cosine and sine are -1 and 0 (decisions
  -- C95), and are compared through show. Turns red if the written state were
  -- not presented, the turn were about the origin or took its sine from
  -- sin pi, 1.2e-16, or a turn-over drew an arrow.
  it "shows the model from its other side in one record, and moves no paper" $ do
    run <- right (onSquare ColouredUp (step_ "Turn the paper over." (turnOver LeftRight)))
    record <- case runRecords run of
      [r] -> pure r
      other -> fail ("expected one record, got " <> show (length other))
    (recordKind record, recordEvidence record) `shouldBe` (Presentation (TurnedOver LeftRight), Presented)
    recordAfter record `shouldBe` recordBefore record
    states <- right (writtenStates run)
    (laid, turned) <- case map stateFrame states of
      [a, b] -> pure (a, b)
      other -> fail ("expected two states, got " <> show (length other))
    show (corners turned) `shouldBe` show [V3 1 0 0, V3 0 0 0, V3 0 1 0, V3 1 1 0]
    frameClasses turned `shouldBe` ["foldedForm"]
    motionsBetween laid turned `shouldBe` Right []
    fmap isJust (wholeModelMotion laid turned) `shouldBe` Right True
    renderRunReport run `shouldContain` ["  presented: the whole model shown from its other side; no paper moved"]
    [l | l <- renderRunReport run, "  moving:" `T.isPrefixOf` l] `shouldBe` []

  -- Top-bottom turns about the horizontal line through the middle: corner
  -- (0, 0) goes to (0, 1), exactly, compared through show. Turns red if
  -- top-bottom turned about the vertical line, as left-right does, or landed
  -- a hair off, as a sine from sin pi would.
  it "turns over top-bottom about the line across the middle" $ do
    run <- right (onSquare ColouredUp (step_ "Turn the paper over top to bottom." (turnOver TopBottom)))
    states <- right (writtenStates run)
    case map stateFrame states of
      [_, turned] -> do
        show (corners turned) `shouldBe` show [V3 0 1 0, V3 1 1 0, V3 1 0 0, V3 0 0 0]
        frameClasses turned `shouldBe` ["foldedForm"]
      other -> expectationFailure ("expected two states, got " <> show (length other))
    -- A turn-over moves no paper: it sweeps nothing and folds nothing.
    map recordCost (runRecords run) `shouldBe` [StepCost 0 0]

  -- After a turn-over the reader sees the white side, so in front is -z on
  -- the paper: a valley the reader folds is a mountain from the coloured
  -- side, -180. Turns red if the reader's side ignored the presentation.
  it "reads a later in front from the side turned up" $ do
    run <- right . onSquare ColouredUp $ do
      step_ "Turn the paper over." (turnOver LeftRight)
      step_ "Fold the bottom half up in front." (fold inFront (LineOnto (edge South) (edge North) Nothing))
    case [r | r <- runRecords run, recordStep r == 2] of
      [folded] -> do
        [letter | (_, _, letter) <- recordNewCreases folded] `shouldBe` [Mountain]
        [a | (_, edges') <- recordHinge folded, EdgeId e <- edges', a <- take 1 (drop e (snd (recordAngles folded)))] `shouldSatisfy` (\angles -> not (null angles) && all (== -180) angles)
      other -> expectationFailure ("expected one record at step 2, got " <> show (length other))

  -- The crane's first three steps, its diagonals, a turn-over and its
  -- midlines, on a plain square: two pre-creases, the turn, two more.
  it "runs the crane's opening on a plain square" $ do
    run <- right . onSquare ColouredUp $ do
      step_ "Crease both diagonals." $ do
        move (FoldAndUnfold ValleyFold (Segment (CornerOf SouthWest) (CornerOf NorthEast)) FlapOfFirstArgument (Just (CornerOf SouthEast)))
        move (FoldAndUnfold ValleyFold (Segment (CornerOf SouthEast) (CornerOf NorthWest)) FlapOfFirstArgument (Just (CornerOf SouthWest)))
      step_ "Turn the paper over." (turnOver LeftRight)
      step_ "Crease both midlines." $ do
        move (FoldAndUnfold ValleyFold (LineOnto (EdgeOf South) (EdgeOf North) Nothing) FlapOfFirstArgument Nothing)
        move (FoldAndUnfold ValleyFold (LineOnto (EdgeOf West) (EdgeOf East) Nothing) FlapOfFirstArgument Nothing)
    map recordKind (runRecords run) `shouldBe` [Precrease, Precrease, Presentation (TurnedOver LeftRight), Precrease, Precrease]

  -- White side up starts with a turn-over left-right (G3): state 0 is
  -- written turned over, showing its back. Turns red if the start were not
  -- presented.
  it "starts turned over when the sequence starts white side up" $ do
    run <- right (onSquare WhiteUp (step_ "Turn the paper over." (turnOver LeftRight)))
    states <- right (writtenStates run)
    case map stateFrame states of
      start : back : _ -> do
        zipWith near (corners start) [V3 1 0 0, V3 0 0 0, V3 0 1 0, V3 1 1 0] `shouldBe` replicate 4 True
        frameClasses start `shouldBe` ["foldedForm"]
        -- Turned over again, the coloured side is up and the sheet lies as
        -- drawn.
        zipWith near (corners back) [V3 0 0 0, V3 1 0 0, V3 1 1 0, V3 0 1 0] `shouldBe` replicate 4 True
        frameClasses back `shouldBe` ["creasePattern"]
      other -> expectationFailure ("expected two states, got " <> show (length other))

  -- Two turn-overs about the same axis put the model back as it began, each
  -- composed onto the presentation before it. Turns red if a turn-over
  -- replaced the presentation rather than composing with it.
  it "turned over twice, shows the model as it began" $ do
    run <- right . onSquare ColouredUp $ do
      step_ "Turn the paper over." (turnOver LeftRight)
      step_ "Turn it back." (turnOver LeftRight)
    states <- right (writtenStates run)
    case map stateFrame states of
      [start, _, back] -> zipWith near (corners back) (corners start) `shouldBe` replicate 4 True
      other -> expectationFailure ("expected three states, got " <> show (length other))
    fmap (snd . recordPresentation) (take 1 (drop 1 (runRecords run))) `shouldSatisfy` all (\p -> matApply (rigidLinear p) (V3 0 0 1) `near` V3 0 0 1)

-- A rotate (#95): the whole model turned on the page about its own middle,
-- the same side up, by whole quarter turns. On the square, a quarter turn
-- anticlockwise about (1/2, 1/2) takes (x, y) to (1 - y, x).
rotating :: Spec
rotating = describe "a rotate" $ do
  let runOn sequence' = checkSequence sequence' >>= runSequence defaultRunSettings M.empty . elaborate
      onSquare = runOn . sequenceOf (header "A square" sheetSquare Nothing)
      positions frame = [V3 x y z | x : y : rest <- verticesCoords frame, let z = case rest of c : _ -> c; [] -> 0]
      corners = take 4 . positions
      near (V3 a b c) (V3 x y z) = maximum (map abs [a - x, b - y, c - z]) < 1e-12
      anticlockwise = [V3 1 0 0, V3 1 1 0, V3 0 1 0, V3 0 0 0]
      clockwise = [V3 0 1 0, V3 0 0 0, V3 1 0 0, V3 1 1 0]
      halfTurned = [V3 1 1 0, V3 0 1 0, V3 0 0 0, V3 1 0 0]
      half = sqrt 0.5
      -- The square after one step, as written.
      turnedBy moves = do
        run <- right (onSquare (step_ "Turn the paper." moves))
        states <- right (writtenStates run)
        case map stateFrame states of
          [_, turned] -> pure turned
          other -> fail ("expected two states, got " <> show (length other))

  -- One record, presented, its two surfaces one, written turned and still
  -- showing its front, so classed a crease pattern; and the page finds no
  -- fold between the two written states. Turns red if the turn went the
  -- other way, were about the origin, turned the paper over, or drew an
  -- arrow.
  it "turns the model a quarter turn about its middle, the same side up, and moves no paper" $ do
    run <- right (onSquare (step_ "Turn the paper a quarter turn." (rotate 2 Anticlockwise)))
    record <- case runRecords run of
      [r] -> pure r
      other -> fail ("expected one record, got " <> show (length other))
    (recordKind record, recordEvidence record) `shouldBe` (Presentation (Rotated 2 Anticlockwise), Presented)
    recordAfter record `shouldBe` recordBefore record
    states <- right (writtenStates run)
    (laid, turned) <- case map stateFrame states of
      [a, b] -> pure (a, b)
      other -> fail ("expected two states, got " <> show (length other))
    zipWith near (corners turned) anticlockwise `shouldBe` replicate 4 True
    frameClasses turned `shouldBe` ["creasePattern"]
    motionsBetween laid turned `shouldBe` Right []
    fmap isJust (wholeModelMotion laid turned) `shouldBe` Right True
    renderRunReport run `shouldContain` ["  presented: the whole model turned on the page, the same side up; no paper moved"]
    [l | l <- renderRunReport run, "  moving:" `T.isPrefixOf` l] `shouldBe` []

  -- Clockwise is the other way, and k eighths one way are 8 - k the other:
  -- the same motion, though each record keeps the turn as written. Turns red
  -- if a direction were ignored or a negative count of quarters lost.
  it "turns clockwise the other way, and six eighths one way as two the other" $ do
    two <- turnedBy (rotate 2 Clockwise)
    zipWith near (corners two) clockwise `shouldBe` replicate 4 True
    six <- turnedBy (rotate 6 Anticlockwise)
    zipWith near (corners six) clockwise `shouldBe` replicate 4 True
    sixBack <- turnedBy (rotate 6 Clockwise)
    zipWith near (corners sixBack) anticlockwise `shouldBe` replicate 4 True
    run <- right (onSquare (step_ "Turn the paper." (rotate 6 Anticlockwise)))
    map recordKind (runRecords run) `shouldBe` [Presentation (Rotated 6 Anticlockwise)]

  -- A half turn has no direction: both are the same motion, and only the
  -- record says which the author wrote, which a page draws (PRD 06).
  it "makes a half turn either way alike, and keeps the way written" $ do
    either' <- mapM (turnedBy . rotate 4) [Clockwise, Anticlockwise]
    [zipWith near (corners f) halfTurned | f <- either'] `shouldBe` replicate 2 (replicate 4 True)
    runs <- mapM (right . onSquare . step_ "Turn the paper." . rotate 4) [Clockwise, Anticlockwise]
    map (map recordKind . runRecords) runs `shouldBe` [[Presentation (Rotated 4 Clockwise)], [Presentation (Rotated 4 Anticlockwise)]]

  -- Folded in half, the model is the top half, centred on (1/2, 3/4), one
  -- wide and a half tall; turned a quarter, it is a half wide and one tall
  -- about the same centre. Turns red if the turn were about the sheet's
  -- middle, where the model was not, or about the origin.
  it "turns about the middle of the model as it is, not of the sheet" $ do
    run <- right . onSquare $ do
      step_ "Fold the bottom half up." (fold valley (LineOnto (edge South) (edge North) Nothing))
      step_ "Turn the model a quarter turn." (rotate 2 Anticlockwise)
    states <- right (writtenStates run)
    let box frame = let ps = positions frame in [minimum (map v3x ps), maximum (map v3x ps), minimum (map v3y ps), maximum (map v3y ps)]
        close a b = abs (a - b) < 1e-12
    case map stateFrame states of
      [_, folded, turned] -> do
        zipWith close (box folded) [0, 1, 1 / 2, 1] `shouldBe` replicate 4 True
        zipWith close (box turned) [1 / 4, 3 / 4, 1 / 4, 5 / 4] `shouldBe` replicate 4 True
      other -> expectationFailure ("expected three states, got " <> show (length other))

  -- A rotate keeps the reader's side, so in front is still +z: a valley the
  -- reader folds is a valley from the coloured side, +180. Turns red if a
  -- rotate turned the paper over, as a turn-over does.
  it "leaves a later in front reading from the same side" $ do
    run <- right . onSquare $ do
      step_ "Turn the paper a quarter turn." (rotate 2 Anticlockwise)
      step_ "Fold the bottom half up in front." (fold inFront (LineOnto (edge South) (edge North) Nothing))
    case [r | r <- runRecords run, recordStep r == 2] of
      [folded] -> do
        [letter | (_, _, letter) <- recordNewCreases folded] `shouldBe` [Valley]
        [a | (_, edges') <- recordHinge folded, EdgeId e <- edges', a <- take 1 (drop e (snd (recordAngles folded)))] `shouldSatisfy` (\angles -> not (null angles) && all (== 180) angles)
      other -> expectationFailure ("expected one record at step 2, got " <> show (length other))

  -- After a turn-over the model is shown from behind, and a rotate turns it
  -- as shown: anticlockwise as the reader now sees it. The record's turn,
  -- its presentation after with the one before undone, is the quarter turn
  -- about +z the author wrote, which is how a page reads it (PRD 06). Turns
  -- red if the rotate were made on the paper before its presentation, which
  -- turns it clockwise as the reader sees it.
  it "turns the model as it is shown, after a turn-over" $ do
    run <- right . onSquare $ do
      step_ "Turn the paper over." (turnOver LeftRight)
      step_ "Turn it a quarter turn." (rotate 2 Anticlockwise)
    states <- right (writtenStates run)
    case map stateFrame states of
      [_, _, turned] -> do
        zipWith near (corners turned) [V3 1 1 0, V3 1 0 0, V3 0 0 0, V3 0 1 0] `shouldBe` replicate 4 True
        frameClasses turned `shouldBe` ["foldedForm"]
      other -> expectationFailure ("expected three states, got " <> show (length other))
    case [recordPresentation r | r <- runRecords run, recordStep r == 2] of
      [(shownBefore, shownAfter)] -> matApply (rigidLinear (shownAfter `Rigid.after` Rigid.inverse shownBefore)) (V3 1 0 0) `shouldSatisfy` near (V3 0 1 0)
      other -> expectationFailure ("expected one record at step 2, got " <> show (length other))

  -- A book's diamond view, the crane opening's first step: one eighth
  -- anticlockwise about the middle carries corner south-west, (0, 0), down
  -- to (1/2, 1/2 - √½), and each other corner round to the next point of
  -- the diamond. Still flat and showing its front, so a crease pattern, and
  -- no fold between the states. Turns red if an odd eighth were refused, or
  -- turned the other way or about the origin.
  it "turns the square to a diamond by one eighth about its middle, the same side up" $ do
    run <- right (onSquare (step_ "Turn the paper to a diamond." (rotate 1 Anticlockwise)))
    record <- case runRecords run of
      [r] -> pure r
      other -> fail ("expected one record, got " <> show (length other))
    (recordKind record, recordEvidence record) `shouldBe` (Presentation (Rotated 1 Anticlockwise), Presented)
    states <- right (writtenStates run)
    (laid, turned) <- case map stateFrame states of
      [a, b] -> pure (a, b)
      other -> fail ("expected two states, got " <> show (length other))
    zipWith near (corners turned) [V3 0.5 (0.5 - half) 0, V3 (0.5 + half) 0.5 0, V3 0.5 (0.5 + half) 0, V3 (0.5 - half) 0.5 0] `shouldBe` replicate 4 True
    frameClasses turned `shouldBe` ["creasePattern"]
    motionsBetween laid turned `shouldBe` Right []
    -- The page finds the whole model turned, though by a rounded √½: what
    -- a presentation's arrow is drawn from.
    fmap isJust (wholeModelMotion laid turned) `shouldBe` Right True
    void (writeSequence noFileHeader run) `shouldBe` Right ()

  -- cos 45° and sin 45° are both √½, which no Double holds; the turn takes
  -- both from sqrt, which IEEE 754 rounds correctly everywhere, so its
  -- entries are exactly ±sqrt 0.5 on every platform (owner decision 10).
  -- Each odd eighth is its own entry in the table, so each is turned once:
  -- 3/8 clockwise is 5/8 anticlockwise, and 7/8 is 1/8 clockwise. Turns red
  -- if it were built from cos and sin, whose values at π/4 differ in the
  -- last bit, or with an entry's sign wrong.
  it "turns an odd eighth by exactly sqrt 0.5, the same bits on every platform" $ do
    let turnOf eighths turning = do
          run <- right (onSquare (step_ "Turn the paper." (rotate eighths turning)))
          case map recordPresentation (runRecords run) of
            [(_, shownAfter)] -> pure (rigidLinear shownAfter)
            other -> fail ("expected one record, got " <> show (length other))
    oneEighth <- turnOf 1 Anticlockwise
    oneEighth `shouldBe` Mat3 (V3 half (-half) 0) (V3 half half 0) (V3 0 0 1)
    three <- turnOf 3 Clockwise
    three `shouldBe` Mat3 (V3 (-half) half 0) (V3 (-half) (-half) 0) (V3 0 0 1)
    five <- turnOf 5 Anticlockwise
    five `shouldBe` three
    threeAnticlockwise <- turnOf 3 Anticlockwise
    threeAnticlockwise `shouldBe` Mat3 (V3 (-half) (-half) 0) (V3 half (-half) 0) (V3 0 0 1)
    sevenAnticlockwise <- turnOf 7 Anticlockwise
    sevenAnticlockwise `shouldBe` Mat3 (V3 half half 0) (V3 (-half) half 0) (V3 0 0 1)

  -- An eighth there and back: √½ rounds, so the corners come back within
  -- rounding of where they were, which need not be exactly, as decision 10
  -- accepted. Applied one after the other, the two turns bring corner
  -- (0, 0) back to (0, -5.6e-17). Turns red if the clockwise eighth were not
  -- the anticlockwise one undone.
  it "comes back within rounding from an eighth there and back" $ do
    run <- right . onSquare $ do
      step_ "Turn the paper to a diamond." (rotate 1 Anticlockwise)
      step_ "Turn it back." (rotate 1 Clockwise)
    states <- right (writtenStates run)
    case map stateFrame states of
      [laid, _, back] -> zipWith near (corners back) (corners laid) `shouldBe` replicate 4 True
      other -> expectationFailure ("expected three states, got " <> show (length other))

-- Re-anchoring (#497, owner decision 3): a move that turns the anchor's
-- paper holds still instead the paper beside its hinge that it does not
-- turn, the largest face there, ties to the lowest vertex mean and then the
-- leftmost (PRD 02 §2.3), and the model stays where it stood on the page.
-- The quarter fold is run three ways: anchored where PRD 09's test 1 anchors
-- it, in the quarter neither fold turns; with no anchor; and anchored in the
-- quarter the second fold turns. It is one folding, so each writes one model.
reanchoring :: Spec
reanchoring = describe "re-anchoring" $ do
  sheet <- runIO (loadFoldFile "examples/quarter-fold-steps.fold" >>= right)
  let runOn sequence' = checkSequence sequence' >>= runSequence defaultRunSettings (M.singleton "examples/quarter-fold-steps.fold" sheet) . elaborate
      anchoredAt p = quarterFold {seqHeader = (seqHeader quarterFold) {hAnchor = Located NoSpan <$> p}}
      framesOf run = map stateFrame <$> writtenStates run
      positions frame = [V3 x y (case rest of z : _ -> z; [] -> 0) | x : y : rest <- verticesCoords frame]
      near (V3 a b c) (V3 x y z) = maximum (map abs [a - x, b - y, c - z]) < 1e-12
      -- Layer orders by the faces they relate, each named by its corners, so
      -- that two numberings of one model compare equal.
      ordersOf frame = sortOn show [(sort (cornersOf f), sort (cornersOf g), orderStacking o) | o <- faceOrders frame, let FaceId f = orderFace o, let FaceId g = orderRelativeTo o]
        where
          cornersOf i = concat (take 1 (drop i (facesVertices frame)))
      sameModel a b = length (positions a) == length (positions b) && and (zipWith near (positions a) (positions b)) && ordersOf a == ordersOf b
      corner x y = MaterialPoint (V2 x y)
  anchoredFrames <- runIO (right (runOn quarterFold >>= framesOf))

  -- An anchor inside corner south-east's triangle of the blintz sheet moves
  -- with it; the one face beside that corner's crease is the middle square,
  -- whose vertex mean is (1/2, 1/2). Turns red if the run refused the fold.
  it "moves an anchor the fold carries onto the face beside the hinge" $ do
    blintzSheet <- loadFoldFile "examples/blintz-base.fold" >>= right
    let carried = sequenceOf (header "t" (sheetFile "examples/blintz-base.fold") (Just (at (19 / 20) (1 / 50)))) (step_ "s" (fold mountain (cornerOf SouthEast `onto` centre)))
    run <- right (checkSequence carried >>= runSequence defaultRunSettings (M.singleton "examples/blintz-base.fold" blintzSheet) . elaborate)
    map recordAnchor (runRecords run) `shouldBe` [(corner 0.95 0.02, corner 0.5 0.5)]

  -- With no anchor line the default is the south-west quarter's vertex mean,
  -- (1/4, 1/4), and the first fold turns that quarter. The run re-anchors
  -- onto the south-east quarter, which lies where it lay on the sheet, so
  -- nothing is placed differently (PRD 02 §2.3's worked example). Turns red
  -- if the run refused, re-anchored onto the north-east quarter, or wrote
  -- each state's faces numbered as the runner holds them.
  it "folds the quarter fold with no anchor, holding still the quarter the fold does not turn" $ do
    run <- right (runOn (anchoredAt Nothing))
    map recordAnchor (runRecords run) `shouldBe` [(corner 0.25 0.25, corner 0.75 0.25), (corner 0.75 0.25, corner 0.75 0.25)]
    map recordPlacement (runRecords run) `shouldBe` replicate 2 (identity, identity)
    map (snd . recordAngles) (runRecords run) `shouldBe` map edgesFoldAngle (otherFrames sheet)
    -- Re-anchoring folds the pattern once more, so the first move costs one
    -- refold more than the second. Turns red if that refold went uncounted.
    map recordCost (runRecords run) `shouldBe` [StepCost 1 9, StepCost 1 8]
    frames <- right (framesOf run)
    zipWith sameModel frames anchoredFrames `shouldBe` [True, True, True]
    case frames of
      start : rest -> map facesVertices rest `shouldBe` replicate (length rest) (facesVertices start)
      [] -> expectationFailure "expected written states"
    renderRunReport run `shouldContain` ["  anchor moved: (0.25, 0.25) to (0.75, 0.25), off the paper the move turns"]

  -- Anchored at (3/4, 3/4), in the quarter the second fold turns. The first
  -- fold has laid the south-west quarter face down on the south-east one;
  -- the second holds both still, they tie on area and height, and the
  -- leftmost is the south-west, face down. Its placement, a half turn about
  -- the line x = 1/2, is taken on, so the model stands where the anchored
  -- run's does, and in front is still towards the reader, which on the paper
  -- folded from that face is -z. Turns red if the placement were dropped,
  -- or the reader's side ignored it. The half turn leaves the second fold's
  -- line, y = 1/2, where it lay, so this test cannot tell whether that line
  -- is carried; the pleat's can.
  it "re-anchors onto paper lying face down, and the model stands where it stood" $ do
    run <- right (runOn (anchoredAt (Just (at (3 / 4) (3 / 4)))))
    map (snd . recordAngles) (runRecords run) `shouldBe` map edgesFoldAngle (otherFrames sheet)
    frames <- right (framesOf run)
    zipWith sameModel frames anchoredFrames `shouldBe` [True, True, True]
    case (runRecords run, frames) of
      ([halved, quartered'], [_, halfway, _]) -> do
        map recordAnchor [halved, quartered'] `shouldBe` [(corner 0.75 0.75, corner 0.75 0.75), (corner 0.75 0.75, corner 0.25 0.25)]
        recordPlacement halved `shouldBe` (identity, identity)
        let (placedBefore, placedAfter) = recordPlacement quartered'
        placedBefore `shouldBe` placedAfter
        matApply (rigidLinear placedAfter) (V3 0 0 1) `shouldSatisfy` near (V3 0 0 (-1))
        -- The second fold's paper before it, shown as its record says, is
        -- where the state before it stands.
        let shown = [applyRigid (displayBefore quartered') p | p <- positions (surfaceFrame (recordBefore quartered'))]
        (length shown, and (zipWith near shown (positions halfway))) `shouldBe` (length (positions halfway), True)
      _ -> expectationFailure ("expected two records and three states, got " <> show (length (runRecords run), length frames))

  -- Turned on the page first, by a quarter turn, which does not commute with
  -- the placement's half turn: the model is placed, then presented, in that
  -- order, in the written states and in a record's display. Turns red if
  -- either composed them the other way round.
  it "places the model, then presents it, when a turn on the page came first" $ do
    let turnedFirst p = sequenceOf (seqHeader (anchoredAt (Just p))) $ do
          step_ "Turn the paper a quarter turn." (rotate 2 Anticlockwise)
          step_ "Fold the left half behind, onto the right." (fold behind (LineOnto (edge West) (edge East) Nothing))
          step_ "Fold the top half down in front, onto the bottom." (fold inFront (LineOnto (edge North) (edge South) Nothing))
    held <- right (runOn (turnedFirst (at (3 / 4) (1 / 4))))
    moved <- right (runOn (turnedFirst (at (3 / 4) (3 / 4))))
    heldFrames <- right (framesOf held)
    movedFrames <- right (framesOf moved)
    zipWith sameModel movedFrames heldFrames `shouldBe` replicate 4 True
    case ([r | r <- runRecords moved, recordStep r == 3], movedFrames) of
      ([refolded], [_, _, halfway, _]) -> do
        let shown = [applyRigid (displayBefore refolded) p | p <- positions (surfaceFrame (recordBefore refolded))]
        (length shown, and (zipWith near shown (positions halfway))) `shouldBe` (length (positions halfway), True)
      _ -> expectationFailure "expected one record at step 3 and four states"

  -- Turned over after re-anchoring onto the quarter lying face down: the
  -- axis goes through the middle of the model as shown, where it stands,
  -- not as folded from the new anchor's face, which lies half a sheet away.
  -- Turns red if a turn-over found the middle on the paper as folded.
  it "turns the model over about its middle as it stands, after re-anchoring" $ do
    let turnedAfter p = sequenceOf (seqHeader (anchoredAt (Just p))) $ do
          step_ "Fold the left half behind, onto the right." (fold behind (LineOnto (edge West) (edge East) Nothing))
          step_ "Fold the top half down in front, onto the bottom." (fold inFront (LineOnto (edge North) (edge South) Nothing))
          step_ "Turn the paper over." (turnOver LeftRight)
    held <- right (runOn (turnedAfter (at (3 / 4) (1 / 4))) >>= framesOf)
    moved <- right (runOn (turnedAfter (at (3 / 4) (3 / 4))) >>= framesOf)
    zipWith sameModel moved held `shouldBe` replicate 4 True

  -- A pleat on the square: the left half folded over the right, then its
  -- outer quarter folded back, which lays that quarter two flips from the
  -- right half, about parallel creases, so moved half a sheet along. Folding
  -- the stack over at x = 7/8 turns the anchor's paper and re-anchors onto
  -- the strip beyond, whichever face held it. Anchored on the quarter, that
  -- strip's h is a move half a sheet back: of the h a fold re-anchors by in
  -- these tests, the only one that is neither the identity nor a half turn,
  -- and so the only one that is not its own inverse. The fold line is found
  -- at x = 3/8 as folded from the quarter, and carried by h's inverse to
  -- x = 7/8 as folded from the strip, where the record says it is at either
  -- anchor. Turns red if it were carried by h, to x = -1/8, or not at all,
  -- leaving it at 3/8: either is off the paper, and the run is refused. And
  -- red if the record kept the line where it was found.
  it "carries the fold line by the inverse of h when h is a move along, not a half turn" $ do
    let pleat holdingAt = sequenceOf (header "A pleat" sheetSquare (Just (at (5 / 8) (1 / 2)))) $ do
          step_ "Pre-crease the quarters and an eighth." $ do
            move (FoldAndUnfold ValleyFold (Segment (at (1 / 4) 0) (at (1 / 4) 1)) FlapOfFirstArgument (Just (CornerOf SouthWest)))
            move (FoldAndUnfold ValleyFold (Segment (at (3 / 4) 0) (at (3 / 4) 1)) FlapOfFirstArgument (Just (CornerOf SouthEast)))
            move (FoldAndUnfold ValleyFold (Segment (at (7 / 8) 0) (at (7 / 8) 1)) FlapOfFirstArgument (Just (CornerOf SouthEast)))
          step_ "Fold the left half over." (move (Fold ValleyFold ToFlat (Segment (at (1 / 2) 0) (at (1 / 2) 1)) FlapOfFirstArgument (Just (CornerOf SouthWest))))
          step_ "Fold the outer quarter back." (move (Fold ValleyFold ToFlat (Segment (at (1 / 4) 0) (at (1 / 4) 1)) FlapOfFirstArgument (Just (at (1 / 8) (1 / 2)))))
          mapM_ (step_ "Hold the quarter still from now on." . anchor) holdingAt
          step_ "Fold the stack over." (move (Fold ValleyFold ToFlat (Segment (at (7 / 8) 0) (at (7 / 8) 1)) FlapOfFirstArgument (Just (at (1 / 8) (1 / 2)))))
    held <- right (runOn (pleat Nothing))
    moved <- right (runOn (pleat (Just (at (1 / 8) (1 / 2)))))
    map (snd . recordAnchor) (drop 5 (runRecords held)) `shouldBe` [corner (15 / 16) (1 / 2)]
    map recordAnchor (drop 5 (runRecords moved)) `shouldBe` [(corner (5 / 8) (1 / 2), corner (1 / 8) (1 / 2)), (corner (1 / 8) (1 / 2), corner (15 / 16) (1 / 2))]
    let lastLine run = case reverse (runRecords run) of
          stackFold : _ -> [(p, d) | ResolvedLine _ p d <- recordResolved stackFold]
          [] -> []
        close (V2 a b) (V2 x y) = all ((< 1e-12) . abs) [a - x, b - y]
    case (lastLine held, lastLine moved) of
      ([(p, d)], [(p', d')]) -> map (uncurry close) [(p, V2 0.875 0.5), (d, V2 0 1), (p', p), (d', d)] `shouldBe` replicate 4 True
      other -> expectationFailure ("expected one resolved line in each last record, got " <> show other)
    heldFrames <- right (framesOf held)
    movedFrames <- right (framesOf moved)
    case (reverse heldFrames, reverse movedFrames) of
      (heldLast : _, movedLast : _) -> sameModel heldLast movedLast `shouldBe` True
      _ -> expectationFailure "expected written states"

  -- Issue #579's sheet: two by one in the file's units, its top-left corner
  -- creased off, so the rest is one face that is not convex. The fold's line
  -- is 3/10 of a sheet length from the west edge, x = 0.6 in the file, and
  -- leaves an L west of it. Anchored inside the L, the fold turns other
  -- paper, and the turn's mesh refuses the L. Anchored east of the line, the
  -- fold turns the anchor's paper and re-anchors onto the L, whose vertex
  -- mean is its own inside corner; the anchor goes to a point inside the L
  -- instead, and the same turn refuses the L the same way. Which point no
  -- run can show while every turn refuses such a face (#586). Turns red if
  -- re-anchoring refused the L itself, as it did, so that which refusal the
  -- fold got depended on the anchor.
  it "refuses a fold onto a face that is not convex the same way at either anchor" $ do
    let lSheet =
          emptyFrame
            { verticesCoords = [[0, 0], [2, 0], [2, 1], [0, 1], [0, 0.5], [0.3, 0.5], [0.3, 1]],
              edgesVertices = [(VertexId a, VertexId b) | (a, b) <- [(0, 1), (1, 2), (2, 6), (6, 3), (3, 4), (4, 0), (4, 5), (5, 6)]],
              edgesAssignment = replicate 6 Border ++ [Valley, Valley]
            }
        sheets = M.singleton "l.fold" squareSheet {keyFrame = lSheet}
        folded heldAt =
          checkSequence (sequenceOf (header "An L-shaped face" (sheetFile "l.fold") (Just heldAt)) (step_ "Fold the right part behind." (move (Fold MountainFold ToFlat (Segment (at (3 / 10) 0) (at (3 / 10) (1 / 2))) FlapOfFirstArgument (Just (at (2 / 5) (3 / 10)))))))
            >>= runSequence defaultRunSettings sheets . elaborate
        refusedAs = \case
          Left (StepRefused 1 _ _ failure) -> Just failure
          _ -> Nothing
    map (refusedAs . folded) [at (1 / 20) (1 / 20), at (3 / 4) (1 / 4)]
      `shouldBe` replicate 2 (Just (FlapRefused (FlapSurface (SurfaceNonConvex (FaceId 0)))))

  -- A square with creases from (0, 0.1) to (0.9, 0.1) to (0.9, 1), folding
  -- edge east or edge west to a line. Folding the east edge creases x = 0.8
  -- first, and the face beside the east edge is then an L whose vertex mean,
  -- (0.9, 11/30), lies on the crease x = 0.9: as a seed it named no one face.
  -- The seed is now a point inside that face (owner decision 51), and the
  -- fold goes on to the turn, which refuses a panel that is not convex as it
  -- does folding the west edge. Turns red if the seed were the vertex mean.
  it "refuses folding either edge to a line the same way, where the face holding the seed is not convex" $ do
    let creased =
          emptyFrame
            { verticesCoords = [[0, 0], [1, 0], [1, 1], [0, 1], [0, 0.1], [0.9, 0.1], [0.9, 1]],
              edgesVertices = [(VertexId a, VertexId b) | (a, b) <- [(0, 1), (1, 2), (2, 6), (6, 3), (3, 4), (4, 0), (4, 5), (5, 6)]],
              edgesAssignment = replicate 6 Border ++ [Valley, Valley]
            }
        sheets = M.singleton "creased.fold" squareSheet {keyFrame = creased}
        edgeTo side x =
          checkSequence (sequenceOf (header "Creased" (sheetFile "creased.fold") Nothing) (step_ "Fold the edge to the line." (move (Fold ValleyFold ToFlat (LineOnto (EdgeOf side) (Segment (at x 0) (at x 1)) Nothing) FlapOfFirstArgument Nothing))))
            >>= runSequence defaultRunSettings sheets . elaborate
        refusedAs = \case
          Left (StepRefused 1 _ _ failure) -> Just failure
          _ -> Nothing
    [refusedAs (edgeTo East (3 / 5)), refusedAs (edgeTo West (1 / 5))]
      `shouldBe` replicate 2 (Just (FlapRefused (FlapSurface (SurfaceNonConvex (FaceId 2)))))

  -- Re-anchoring twice, onto paper turned about axes 45° apart, on the
  -- square base. The diagonal fold lays the lower right half behind; the
  -- fold along the middle carries the anchor and re-anchors onto a triangle
  -- the diagonal fold turned, so the placement is a half turn about the
  -- diagonal; swinging the bottom layers back re-anchors again, onto a
  -- triangle turned about the vertical middle from the first. Two half turns
  -- about axes 45° apart compose to a quarter turn on the page, and to the
  -- opposite quarter turn in the other order, so the run refuses unless each
  -- re-anchoring takes on its h after the placement it had. Turns red then.
  it "re-anchors twice, taking each turn on after the placement before it" $ do
    squareBase <- loadFoldFile "examples/square-base.fold" >>= right
    let twice = sequenceOf (header "t" (sheetFile "examples/square-base.fold") (Just (at (1 / 3) (5 / 6)))) $ do
          _ <- step "a" "Fold the lower right half behind along the diagonal." (move (Fold MountainFold ToFlat (Segment (at 0 0) (at 1 1)) FlapOfFirstArgument (Just (at (2 / 3) (1 / 6)))))
          b <- step "b" "Fold the top down in front along the middle." (move (Fold ValleyFold ToFlat (Segment (at 0 (1 / 2)) (at (1 / 2) (1 / 2))) FlapOfFirstArgument (Just (at (1 / 3) (5 / 6)))))
          step_ "Swing the bottom layers back behind." (move (Fold MountainFold ToFlat (hingeOf b) FlapOfFirstArgument (Just (at (1 / 3) (1 / 6)))))
    run <- right (checkSequence twice >>= runSequence defaultRunSettings (M.singleton "examples/square-base.fold" squareBase) . elaborate)
    map (snd . recordAnchor) (runRecords run) `shouldBe` [corner (1 / 3) (5 / 6), corner (1 / 3) (1 / 6), corner (2 / 3) (1 / 6)]
    frames <- right (framesOf run)
    case (runRecords run, frames) of
      ([_, _, swung], [_, _, folded, _]) -> do
        let placed = snd (recordPlacement swung)
        (matApply (rigidLinear placed) (V3 0 0 1), abs (v3z (matApply (rigidLinear placed) (V3 1 0 0)))) `shouldSatisfy` (\(z, tilt) -> near z (V3 0 0 1) && tilt < 1e-12)
        abs (v3x (matApply (rigidLinear placed) (V3 1 0 0))) `shouldSatisfy` (< 1e-12)
        let shown = [applyRigid (displayBefore swung) p | p <- positions (surfaceFrame (recordBefore swung))]
        (length shown, and (zipWith near shown (positions folded))) `shouldBe` (length (positions folded), True)
      _ -> expectationFailure "expected three records and four states"

  -- `anchor P` re-anchors on demand onto the face P lies strictly inside,
  -- with the anchor at P, and moves no paper (PRD 02 §2.3). After the first
  -- fold the south-west quarter lies face down behind the south-east one;
  -- holding it still from then on and folding again writes the model the
  -- anchored quarter fold writes, the state after the anchor being the state
  -- before it. Turns red if the move moved the model on the page, made no
  -- record, or the record's placement were not the new one.
  describe "anchor P" $ do
    let holding p = sequenceOf (seqHeader quarterFold) $ do
          step_ "Fold the left half behind, onto the right." (fold behind (LineOnto (edge West) (edge East) Nothing))
          step_ "Hold that paper still from now on." (anchor p)
          step_ "Fold the top half down in front, onto the bottom." (fold inFront (LineOnto (edge North) (edge South) Nothing))
        refusalOf = \case
          Left (ResolveRefused _ _ _ problem) -> Just problem
          _ -> Nothing

    it "holds the paper it names still from then on, and moves no paper" $ do
      run <- right (runOn (holding (at (1 / 4) (1 / 4))))
      case [r | r <- runRecords run, recordStep r == 2] of
        [r] -> do
          (recordKind r, recordEvidence r) `shouldBe` (Anchoring, NoMotion)
          recordAnchor r `shouldBe` (corner 0.75 0.25, corner 0.25 0.25)
          -- No sweep, and one refold: re-anchoring's, from the fold the
          -- move before kept. Turns red if the runner's refolds were not
          -- added to this record.
          recordCost r `shouldBe` StepCost 0 1
          recordAfter r `shouldBe` recordBefore r
          let (placedBefore, placedAfter) = recordPlacement r
          placedBefore `shouldBe` placedAfter
          matApply (rigidLinear placedAfter) (V3 0 0 1) `shouldSatisfy` near (V3 0 0 (-1))
        other -> expectationFailure ("expected one record at step 2, got " <> show (length other))
      frames <- right (framesOf run)
      case anchoredFrames of
        [start, halved, quartered'] -> zipWith sameModel frames [start, halved, halved, quartered'] `shouldBe` replicate 4 True
        other -> expectationFailure ("expected three anchored states, got " <> show (length other))
      case frames of
        start : rest -> map facesVertices rest `shouldBe` replicate (length rest) (facesVertices start)
        [] -> expectationFailure "expected written states"
      map (KM.lookup "senbazuru:assurance" . frameExtras) (take 1 (drop 2 frames)) `shouldBe` [Just (toJSON [object ["move" .= (1 :: Int), "evidence" .= ("NoMotion" :: T.Text)]])]
      renderRunReport run `shouldContain` ["  nothing turned: no paper moved", "  anchor moved: (0.75, 0.25) to (0.25, 0.25), where the move names it"]
      length [l | l <- renderRunReport run, "  moving:" `T.isPrefixOf` l] `shouldBe` 2

    -- Paper in the face already held still: the anchor moves to it, and
    -- nothing else does. Turns red if re-anchoring onto the first face
    -- renumbered or moved anything.
    it "moves only the anchor when P is in the face already held still" $ do
      run <- right (runOn (holding (at (4 / 5) (1 / 5))))
      case [r | r <- runRecords run, recordStep r == 2] of
        [r] -> (recordAnchor r, recordPlacement r) `shouldBe` ((corner 0.75 0.25, corner 0.8 0.2), (identity, identity))
        other -> expectationFailure ("expected one record at step 2, got " <> show (length other))
      frames <- right (framesOf run)
      case anchoredFrames of
        [start, halved, quartered'] -> zipWith sameModel frames [start, halved, halved, quartered'] `shouldBe` replicate 4 True
        other -> expectationFailure ("expected three anchored states, got " <> show (length other))

    -- A region names paper strictly inside one face; the vertical midline
    -- is a crease, strictly inside none.
    it "refuses a point on a crease, which is in no one face" $ do
      let refused = runOn (holding (at (1 / 2) (1 / 4)))
      case refusalOf refused of
        Just (NotInOneFace _ 0) -> pure ()
        other -> expectationFailure ("expected NotInOneFace, got " <> show other)
      either refusalKindOf (const Nothing) refused `shouldBe` Just (RefusalKind "NotInOneFace")

    -- Paper is named only on paper lying flat, so a half folded up to 90°
    -- leaves nothing an anchor can be named on.
    it "refuses on paper standing in the air, where no paper is named" $ do
      let standing = sequenceOf (seqHeader quarterFold) $ do
            step_ "Fold the left half up." (move (Fold MountainFold (Degrees 90) (LineOnto (edge West) (edge East) Nothing) FlapOfFirstArgument Nothing))
            step_ "Hold the left half still." (anchor (at (1 / 4) (1 / 4)))
      case refusalOf (runOn standing) of
        Just (ConstructionInTheAir _) -> pure ()
        other -> expectationFailure ("expected ConstructionInTheAir, got " <> show other)

  -- Turned back, the second fold first and then the first, across that
  -- re-anchoring. The first fold's paper holds the anchor by then, so
  -- turning it back re-anchors again, onto the south-east quarter, and the
  -- sheet ends where it began. Turns red if an unfold carried the anchor's
  -- face, which moves the model on the page and fails the join check.
  it "turns back across a re-anchoring, and re-anchors again when a turn back carries the anchor" $ do
    let opened = sequenceOf (seqHeader (anchoredAt (Just (at (3 / 4) (3 / 4))))) $ do
          half <- step "half" "Fold the left half behind, onto the right." (fold behind (LineOnto (edge West) (edge East) Nothing))
          quarter <- step "quarter" "Fold the top half down in front, onto the bottom." (fold inFront (LineOnto (edge North) (edge South) Nothing))
          step_ "Unfold the top half." (unfold [quarter])
          step_ "Unfold the left half." (unfold [half])
    run <- right (runOn opened)
    map recordAnchor (runRecords run) `shouldBe` [(corner 0.75 0.75, corner 0.75 0.75), (corner 0.75 0.75, corner 0.25 0.25), (corner 0.25 0.25, corner 0.25 0.25), (corner 0.25 0.25, corner 0.75 0.25)]
    frames <- right (framesOf run)
    case frames of
      [start, _, _, _, end] -> (length (positions end), and (zipWith near (positions end) (positions start))) `shouldBe` (length (positions start), True)
      other -> expectationFailure ("expected five states, got " <> show (length other))

-- A re-anchoring that would hold still a face standing up is refused (PRD 02
-- §2.3): no side of the model would face the reader. On the accordion, four
-- panels in a row: fold the left half behind, which re-anchors onto the
-- third panel; fold the third and second panels over to the right in front,
-- which re-anchors onto the first, lying face down; stand them up again at
-- 90°. Turning the first fold back now carries the anchor, and the face it
-- would hold still, the third panel, stands at 90°. Turns red if the check
-- were dropped: the turn back is then refused for its path instead.
reanchoringOntoStandingPaper :: Spec
reanchoringOntoStandingPaper = describe "re-anchoring onto paper standing up" $ do
  sheet <- runIO (loadFoldFile "examples/accordion.fold" >>= right)
  it "is refused, saying where the face stands" $ do
    let standing = sequenceOf (header "t" (sheetFile "examples/accordion.fold") Nothing) $ do
          a <- step "a" "Fold the left half behind." (move (Fold MountainFold ToFlat (Segment (at (1 / 2) 0) (at (1 / 2) 1)) FlapOfFirstArgument (Just (at (1 / 8) (1 / 2)))))
          b <- step "b" "Fold the middle panel over to the right, in front." (move (Fold ValleyFold ToFlat (Segment (at (3 / 4) 0) (at (3 / 4) 1)) FlapOfFirstArgument (Just (at (5 / 8) (1 / 2)))))
          step_ "Stand it up again." (move (Fold ValleyFold (Degrees 90) (hingeOf b) FlapOfFirstArgument (Just (at (5 / 8) (1 / 2)))))
          step_ "Unfold the left half." (unfold [a])
    case checkSequence standing >>= runSequence defaultRunSettings (M.singleton "examples/accordion.fold" sheet) . elaborate of
      Left err@(StepRefused 4 _ _ (ReanchorNotFlat (V2 x y) tilt)) -> do
        (x, y) `shouldBe` (0.625, 0.5)
        abs (tilt - 90) `shouldSatisfy` (< 1e-9)
        refusalKindOf err `shouldBe` Just (RefusalKind "ReanchorNotFlat")
      other -> expectationFailure ("expected step 4 refused as ReanchorNotFlat, got " <> either show (const "a run") other)

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
      -- One fold behind along a line up the square's middle, from an anchor
      -- given, and what such a fold's record says about the paper.
      upTheMiddle anchoredAt line seed = onSquare (Just anchoredAt) ColouredUp (step_ "Fold the right half behind." (move (Fold MountainFold ToFlat line FlapOfFirstArgument seed)))
      facts r = (recordNewCreases r, recordHinge r, recordAngles r)
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

  -- Through the centre at right angles to edge south is the line up the
  -- middle, so the fold is the one along [midpoint of edge south, midpoint
  -- of edge north]: the same crease, hinge and angles, whether the anchor
  -- lies on the half held still or on the half that turns, where the move
  -- re-anchors and carries its line with the paper. Both lines run north,
  -- so their creases' ends come in one order. Neither line says which side
  -- moves, so the moving seed, corner south-east, must. Turns red if O4
  -- were refused, or its line drawn along L rather than across it.
  it "folds through a point at right angles to a line as along the same line through two points" $ do
    let o4 = PerpendicularThrough (edge South) centre
        throughTwo = Segment (MidpointOfEdge South) (MidpointOfEdge North)
    forM_ [at (1 / 4) (1 / 4), at (3 / 4) (1 / 4)] $ \anchoredAt -> do
      o4Run <- right (upTheMiddle anchoredAt o4 (Just (corner SouthEast)))
      twoRun <- right (upTheMiddle anchoredAt throughTwo (Just (corner SouthEast)))
      o4Record <- one (runRecords o4Run)
      twoRecord <- one (runRecords twoRun)
      map ends (recordNewCreases o4Record) `shouldBe` [([V2 0.5 0, V2 0.5 1], [EdgeId 6], Mountain)]
      facts o4Record `shouldBe` facts twoRecord
      renderRunReport o4Run `shouldContain` ["  line perpendicular to edge south through centre: through (0.5, 0.5), along (0, 1)"]
    case upTheMiddle (at (1 / 4) (1 / 4)) o4 Nothing of
      Left (StepRefused _ _ _ (Selecting SeedMissing)) -> pure ()
      other -> expectationFailure ("expected the line refused as saying no side moves, got " <> either (show . explain) (const "a run") other)

  -- The line laid onto another here, the middle across onto the middle up,
  -- has two answers, the diagonals, so L needs a nearest P. The refusal is
  -- named as L's, says where the nearest goes, and keeps its kind, so that
  -- expect refused NeedsNearest still matches it (#570). Turns red if L's
  -- refusal were reported as the whole line's, or lost its kind.
  it "names the line inside it when that line is refused, keeping its refusal's kind" $ do
    let crossing = LineOnto (Segment (at 0 (1 / 2)) (at 1 (1 / 2))) (Segment (at (1 / 2) 0) (at (1 / 2) 1)) Nothing
    case upTheMiddle (at (1 / 4) (1 / 4)) (PerpendicularThrough crossing (at (1 / 4) (1 / 4))) (Just (corner SouthEast)) of
      Left err@(ResolveRefused _ _ written (InsideLine inner (NeedsNearest answers))) -> do
        (written, inner, length answers) `shouldBe` ("perpendicular to ([(0, 1/2), (1, 1/2)] to [(1/2, 0), (1/2, 1)]) through (1/4, 1/4)", "[(0, 1/2), (1, 1/2)] to [(1/2, 0), (1/2, 1)]", 2)
        refusalKindOf err `shouldBe` Just (RefusalKind "NeedsNearest")
        explain err `shouldSatisfy` T.isInfixOf "the line inside it, \"[(0, 1/2), (1, 1/2)] to [(1/2, 0), (1/2, 1)]\", is refused, and a nearest P for it goes right after it, where it is written, not after the whole line: the construction has 2 answers"
      other -> expectationFailure ("expected L refused as needing a nearest P, got " <> either (show . explain) (const "a run") other)

  -- The square folded in half across its middle and unfolded, then folded
  -- at right angles to that hinge through the centre, which is the line up
  -- the middle: a hinge inside another line is found as one standing alone
  -- is (#570). The step that folds in half also turns the paper over, which
  -- turns no paper about a hinge, so the step still has one hinge. Turns
  -- red if a hinge inside another line were refused, or laid in a direction
  -- other than its crease's, or if a turn-over counted as a second hinge.
  it "folds at right angles to a hinge as along the same line through two points" $ do
    let afterHalf lineFrom = onSquare (Just (at (1 / 4) (1 / 4))) ColouredUp $ do
          half <- step "half" "Fold the top half down, and turn the paper over." $ do
            move (Fold ValleyFold ToFlat (Segment (MidpointOfEdge West) (MidpointOfEdge East)) FlapOfFirstArgument (Just (corner NorthEast)))
            turnOver LeftRight
          step_ "Unfold it." (unfold [half])
          step_ "Fold the right half behind." (move (Fold MountainFold ToFlat (lineFrom half) FlapOfFirstArgument (Just (corner SouthEast))))
    o4Run <- right (afterHalf (\half -> PerpendicularThrough (hingeOf half) centre))
    twoRun <- right (afterHalf (const (Segment (MidpointOfEdge South) (MidpointOfEdge North))))
    length (runRecords o4Run) `shouldBe` 4
    map facts (runRecords o4Run) `shouldBe` map facts (runRecords twoRun)

  -- A step that only turns the paper over turned no paper about a hinge,
  -- and is refused as having made none, not as a line along no crease.
  -- Turns red if its turn-over were taken for a move with a hinge.
  it "refuses the hinge of a step that turned no paper" $ do
    let overThen = onSquare (Just (at (1 / 4) (1 / 4))) ColouredUp $ do
          flipped <- step "flipped" "Turn the paper over." (turnOver LeftRight)
          step_ "Fold the right half behind." (move (Fold MountainFold ToFlat (PerpendicularThrough (hingeOf flipped) centre) FlapOfFirstArgument (Just (corner SouthEast))))
    case overThen of
      Left (ResolveRefused _ _ _ (InsideLine "hinge of flipped" (HingeOfNotOneMove (Name "flipped") 0))) -> pure ()
      other -> expectationFailure ("expected the hinge refused as of no turn, got " <> either (show . explain) (const "a run") other)

  -- Pre-creases across x = 1/4 and y = 1/4 so the last fold runs along
  -- creases the paper has; the square folded in half across its middle and
  -- unfolded; then the north-east corner folded over, which carries the
  -- east end of that crease round to run north-south. The crease the half
  -- fold turned about no longer lies on one line. Taking its first piece,
  -- the fold at right angles to it ran up x = 1/4 or along y = 1/4, by which
  -- way the half fold's line had been written. Turns red if a bent hinge
  -- gave a line, written either way, alone or inside another.
  it "refuses a hinge a later fold has bent, however its crease was written" $ do
    let bentThen halfLine lineFrom = onSquare (Just (at (1 / 2) (3 / 8))) ColouredUp $ do
          step_ "Pre-crease x = 1/4." (move (FoldAndUnfold ValleyFold (Segment (at (1 / 4) 0) (at (1 / 4) 1)) FlapOfFirstArgument (Just (corner SouthWest))))
          step_ "Pre-crease y = 1/4." (move (FoldAndUnfold ValleyFold (Segment (at 0 (1 / 4)) (at 1 (1 / 4))) FlapOfFirstArgument (Just (corner SouthWest))))
          half <- step "half" "Fold the top half down." (move (Fold ValleyFold ToFlat halfLine FlapOfFirstArgument (Just (corner NorthEast))))
          step_ "Unfold it." (unfold [half])
          step_ "Fold the north-east corner down." (move (Fold ValleyFold ToFlat (Segment (at (1 / 4) 1) (at 1 (1 / 4))) FlapOfFirstArgument (Just (corner NorthEast))))
          step_ "Fold along the half crease, or across it." (move (Fold ValleyFold ToFlat (lineFrom half) FlapOfFirstArgument (Just (corner SouthWest))))
        bent = \case
          ResolveRefused _ _ _ (InsideLine _ (NotRunYet what)) -> "bent" `T.isInfixOf` what
          ResolveRefused _ _ _ (NotRunYet what) -> "bent" `T.isInfixOf` what
          _ -> False
    forM_ [Segment (MidpointOfEdge West) (MidpointOfEdge East), Segment (MidpointOfEdge East) (MidpointOfEdge West)] $ \halfLine ->
      forM_ [\half -> PerpendicularThrough (hingeOf half) (at (1 / 4) (1 / 4)), hingeOf] $ \lineFrom ->
        case bentThen halfLine lineFrom of
          Left err | bent err -> pure ()
          other -> expectationFailure ("expected the bent hinge refused, got " <> either (show . explain) (const "a run") other)

  -- A point typed 1/2000 above the middle of the south side is that far from
  -- (1/2, 0), the end of the crease each fold here makes, and is near no
  -- vertex the paper had before. So each fold runs at every anchor, and
  -- makes the same crease, hinge and angles at each. The two-point line and
  -- the one at right angles move the east half; laying one point onto
  -- another moves the west, where its first point is, so the anchors west
  -- and east of the middle swap roles. The third anchor is on the new
  -- crease, and moves off it (decisions C19). A point as near a corner the
  -- paper already has is a near miss at every anchor. Turns red if a move
  -- that re-anchors measured near misses against its own new crease, or if
  -- no move measured them.
  it "decides a near miss on the paper as it was before the move, at every anchor" $ do
    let nearSouth = at (1 / 2) (1 / 2000)
        west = at (1 / 4) (1 / 4)
        onCrease = at (1 / 2) (1 / 4)
        east = at (3 / 4) (1 / 4)
        close (V2 a b) (V2 x y) = all ((< 1e-12) . abs) [a - x, b - y]
    forM_
      [ (Segment nearSouth (at (1 / 2) 1), Just (corner SouthEast)),
        (PerpendicularThrough (edge South) nearSouth, Just (corner SouthEast)),
        (Onto (at (2498 / 5000) (1 / 5000)) (at (2502 / 5000) (1 / 5000)), Nothing)
      ]
      $ \(line, seed) -> do
        let recordAt anchoredAt = right (upTheMiddle anchoredAt line seed) >>= one . runRecords
        westward <- recordAt west
        onIt <- recordAt onCrease
        eastward <- recordAt east
        (facts onIt, facts eastward) `shouldBe` (facts westward, facts westward)
        case map ends (recordNewCreases westward) of
          [([a, b], _, Mountain)] -> (close a (V2 0.5 0), close b (V2 0.5 1)) `shouldBe` (True, True)
          other -> expectationFailure ("expected one new mountain crease, got " <> show other)
    forM_ [west, onCrease, east] $ \anchoredAt -> case upTheMiddle anchoredAt (Segment (at (1 / 2) 0) (at (1 / 2000) 1)) (Just (corner SouthEast)) of
      Left (ResolveRefused _ _ _ (NearMiss _ 3 _ _)) -> pure ()
      other -> expectationFailure ("expected a near miss of corner north-west, vertex 3, got " <> either (show . explain) (const "a run") other)

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
    -- One refold creasing the square and one moving the anchor, on top of a
    -- blintz move's 8. Turns red if either went uncounted.
    recordCost record `shouldBe` StepCost 1 10

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

    -- An L whose arms are a tenth wide: its corners average to (11/30,
    -- 11/30), in the empty quarter. Its ears are the corners at the ends of
    -- its arms; those at (1, 0) and (0, 1) are the largest and tie, and the
    -- first's mean, (2/3, 1/30), is the lower (owner decision 51). Turns red
    -- if the anchor were taken without asking whether it lies on paper, or
    -- were refused, as it was before.
    it "anchors a face whose vertex mean is off it at its largest ear's mean" $ do
      state <- right (sheetState (withKey (const thinL) squareSheet))
      case stateAnchor state of
        MaterialPoint (V2 x y) -> (x, y) `shouldSatisfy` (\(a, b) -> abs (a - 2 / 3) < 1e-12 && abs (b - 1 / 30) < 1e-12)

    -- The same L with an anchor in its header, in the arm up the west side,
    -- turned over. Turns red if the start refused the default before reading
    -- the header's anchor, as it did when a default off its face was refused.
    it "runs from a header's anchor on a face whose vertex mean is off it" $ do
      let onThinL = sequenceOf (header "A thin L" (sheetFile "thin-l.fold") (Just (at (1 / 20) (1 / 2)))) (step_ "Turn it over." (turnOver LeftRight))
      run <- right (checkSequence onThinL >>= runSequence defaultRunSettings (M.singleton "thin-l.fold" (withKey (const thinL) squareSheet)) . elaborate)
      map recordAnchor (runRecords run) `shouldBe` [(MaterialPoint (V2 (1 / 20) (1 / 2)), MaterialPoint (V2 (1 / 20) (1 / 2)))]

    -- A sheet 1.5e-9 high, its tolerance a billionth of its diagonal, about
    -- 1e-9: its vertex mean is 0.75e-9 from its long sides, and its ears'
    -- means 0.5e-9. Turns red if a point too near the outline were taken.
    it "with no point in any face clear of its outline" $ do
      let thin = emptyFrame {verticesCoords = [[0, 0], [1, 0], [1, 1.5e-9], [0, 1.5e-9]], edgesVertices = [(VertexId i, VertexId ((i + 1) `mod` 4)) | i <- [0 .. 3]], edgesAssignment = replicate 4 Border}
      sheetState (withKey (const thin) squareSheet) `shouldBe` Left NoRoomForAnchor

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
    thinL = emptyFrame {verticesCoords = [[0, 0], [1, 0], [1, 0.1], [0.1, 0.1], [0.1, 1], [0, 1]], edgesVertices = [(VertexId i, VertexId ((i + 1) `mod` 6)) | i <- [0 .. 5]], edgesAssignment = replicate 6 Border, facesVertices = [map VertexId [0 .. 5]]}

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
