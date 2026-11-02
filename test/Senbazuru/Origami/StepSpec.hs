-- |
-- Tests for working out what a step of a diagram does.
--
-- The thing worth pinning hardest is that the answer is derived and not
-- assumed: swap the two frames and the motion has to reverse, because nothing
-- in the code knows which way a fold "usually" goes.
module Senbazuru.Origami.StepSpec (spec) where

import Control.Monad (forM_)
import Data.Aeson (toJSON)
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as M
import Data.Maybe (isJust)
import FlapExample (alignedFlap, singleFlap, touchingFlap)
import Senbazuru.Fold.Creasing (NewCreaseAngle (..), creaseAllAlongWith)
import Senbazuru.Fold.Load (decodeFoldFile)
import Senbazuru.Fold.Query (FoldError (..), frameVertices)
import Senbazuru.Fold.Types
  ( Assignment (..),
    EdgeId (..),
    FaceId (..),
    Frame (..),
    VertexId (..),
    allFrames,
    emptyFrame,
    keyFrame,
  )
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace (norm, (^-^))
import Senbazuru.Origami.Flap (checkFlap, flapAt, prepareFlap)
import Senbazuru.Origami.Folding (foldFrame, foldFrameWith)
import Senbazuru.Origami.HingeSweep (defaultSweepSettings)
import Senbazuru.Origami.Step
import Senbazuru.Origami.Surface (materialFrame, surfaceFromFolded)
import Senbazuru.Sequence.Build (at, header, move, sequenceOf, sheetSquare, step_)
import Senbazuru.Sequence.Build qualified as Build
import Senbazuru.Sequence.Check (checkSequence)
import Senbazuru.Sequence.Elaborate (elaborate)
import Senbazuru.Sequence.Record (WrittenState (..), displayAfter, displayBefore, displayedFrame, recordAfter, recordBefore, recordStep, runRecords, writtenStates)
import Senbazuru.Sequence.Run (defaultRunSettings, runSequence)
import Senbazuru.Sequence.Syntax (Amount (..), Compass (..), Corner (..), Layers (..), Line (..), Move (..), PageAxis (..), Point (..), Sense (..), Sequence)
import Test.Hspec
import Test.SequenceExamples (creasedTwice)

steps :: IO [Frame]
steps = do
  bytes <- BS.readFile "test/fixtures/quarter-fold-steps.fold"
  case decodeFoldFile bytes of
    Left err -> fail ("decode failed: " <> err)
    Right f -> pure (allFrames f)

-- | Two square flaps either side of a square that does not move, joined only
-- through it: the shape of "fold both wings at once".
--
-- Faces 0 and 2 are the flaps and face 1 is the middle. Frames differ only in
-- where the flaps are.
twoFlaps :: [[Double]] -> Frame
twoFlaps coords =
  emptyFrame
    { verticesCoords = coords,
      edgesVertices =
        [ (VertexId 0, VertexId 1),
          (VertexId 2, VertexId 3),
          (VertexId 4, VertexId 5)
        ],
      edgesAssignment = [Valley, Valley, Valley],
      facesVertices =
        [ map VertexId [0, 1, 3, 2],
          map VertexId [2, 3, 5, 4],
          map VertexId [4, 5, 7, 6]
        ]
    }

flapsApart, flapsFolded :: Frame
flapsApart =
  twoFlaps [[0, 0], [0, 1], [1, 0], [1, 1], [2, 0], [2, 1], [3, 0], [3, 1]]
-- Both outer squares folded in on top of the middle one.
flapsFolded =
  twoFlaps [[2, 0], [2, 1], [1, 0], [1, 1], [2, 0], [2, 1], [1, 0], [1, 1]]

spec :: Spec
spec = do
  presentation
  placement
  growing
  describe "the folding sequence fixture" $ do
    it "sees the left half swing onto the right" $ do
      fs <- steps
      motionsBetween (head fs) (fs !! 1)
        `shouldBe` Right
          [ Motion
              { motionFaces = [FaceId 2, FaceId 3],
                motionCreases = [EdgeId 8, EdgeId 10],
                motionFrom = V3 0.25 0.5 0,
                motionTo = V3 0.75 0.5 0
              }
          ]

    it "sees the top half fold down on the next step" $ do
      fs <- steps
      fmap (map (\m -> (motionFaces m, motionFrom m, motionTo m))) (motionsBetween (fs !! 1) (fs !! 2))
        `shouldBe` Right [([FaceId 1, FaceId 2], V3 0.75 0.75 0, V3 0.75 0.25 0)]

    it "reverses when the frames are given the other way round" $ do
      -- The direction is subtracted from the two frames, not assumed. Nothing
      -- here knows which way a fold "usually" goes, and this is what says so.
      fs <- steps
      let forwards = motionsBetween (head fs) (fs !! 1)
          backwards = motionsBetween (fs !! 1) (head fs)
      fmap (map motionFrom) backwards `shouldBe` fmap (map motionTo) forwards
      fmap (map motionTo) backwards `shouldBe` fmap (map motionFrom) forwards

    it "finds nothing between a frame and itself" $ do
      fs <- steps
      motionsBetween (head fs) (head fs) `shouldBe` Right []

  describe "several things moving at once" $ do
    it "gives each connected group its own motion" $ do
      -- Two flaps folding inwards. One arrow between them would point at the
      -- middle, where no paper goes.
      let got = fmap (map (\m -> (motionFaces m, motionFrom m, motionTo m))) (motionsBetween flapsApart flapsFolded)
      got
        `shouldBe` Right
          [ ([FaceId 0], V3 0.5 0.5 0, V3 1.5 0.5 0),
            ([FaceId 2], V3 2.5 0.5 0, V3 1.5 0.5 0)
          ]

    it "keeps paper that moves together in one group" $ do
      -- The two faces of the fixture's left half share an edge, so they are one
      -- flap and get one arrow, not two.
      fs <- steps
      fmap (map (length . motionFaces)) (motionsBetween (head fs) (fs !! 1))
        `shouldBe` Right [2]

  describe "what it will not compare" $ do
    it "refuses two frames that are not the same model" $ do
      let smaller = flapsApart {facesVertices = take 2 (facesVertices flapsApart)}
      motionsBetween flapsApart smaller
        `shouldBe` Left (FramesDiffer "faces_vertices" 3 2)

    it "refuses two frames whose faces are joined up differently" $ do
      -- Same count, different paper. Matching face i to face i across them would
      -- take the centre of one flap and the centre of an unrelated one as the
      -- two ends of a motion, and draw an arrow between them.
      let shuffled = flapsApart {facesVertices = reverse (facesVertices flapsApart)}
      motionsBetween flapsApart shuffled
        `shouldBe` Left (FramesDisagree "faces_vertices" 0)

    it "still finds the motion when neither frame records a fold angle" $ do
      -- Positions are what the reader is looking at. A frame may record no
      -- angles at all, and the paper has still moved.
      fmap (map motionCreases) (motionsBetween flapsApart flapsFolded)
        `shouldBe` Right [[], []]

-- | A turn of the whole model is not a fold (PRD 05, L3). Asked of the
-- quarter fold's states, each turned over left-right about its own middle as
-- decisions D5 turns it: (x, y, z) to (2cx - x, y, 2cz - z), with (cx, cz) the
-- middle of its x and z ranges.
presentation :: Spec
presentation = describe "a turn of the whole model" $ do
  -- On the flat sheet the axis runs up x = 1/2, through two edge midpoints
  -- and the centre, which stay where they were; the folded state, x from 1/2
  -- to 1, has no vertex on its axis at x = 3/4. Turns red if a turn-over had
  -- to move every vertex, or if either turn were not found.
  it "gives no motion, and one turn of the whole model, when the model is turned over" $ do
    frames <- steps
    (flat, folded) <- case frames of
      first' : rest@(_ : _) -> pure (first', last rest)
      _ -> fail "the sequence has fewer than two states"
    let turnOver frame = do
          points <- either (fail . show) pure (frameVertices frame)
          let xs = [x | V3 x _ _ <- points]
              zs = [z | V3 _ _ z <- points]
              cx = (minimum xs + maximum xs) / 2
              cz = (minimum zs + maximum zs) / 2
              turned = [V3 (2 * cx - x) y (2 * cz - z) | V3 x y z <- points]
          pure (length [() | (p, q) <- zip points turned, norm (p ^-^ q) < 1e-12], frame {verticesCoords = [[x, y, z] | V3 x y z <- turned]})
    (stillOnFlat, flatTurned) <- turnOver flat
    (stillOnFolded, foldedTurned) <- turnOver folded
    (stillOnFlat, stillOnFolded) `shouldBe` (3, 0)
    motionsBetween flat flatTurned `shouldBe` Right []
    motionsBetween folded foldedTurned `shouldBe` Right []
    fmap isJust (wholeModelMotion flat flatTurned) `shouldBe` Right True
    fmap isJust (wholeModelMotion folded foldedTurned) `shouldBe` Right True

  -- A fold holds a face still, so no one motion fits the whole model; and a
  -- pair where nothing moved is no turn either. Turns red if a fold were
  -- taken for a turn-over, or the identity counted as one.
  it "finds none for a fold, or for a state and itself" $ do
    frames <- steps
    case frames of
      first' : second : _ -> do
        wholeModelMotion first' second `shouldBe` Right Nothing
        wholeModelMotion first' first' `shouldBe` Right Nothing
      _ -> expectationFailure "the sequence has fewer than two states"

-- | 05 L5's placement (R-05-17, R-05-18): a later frame's vertices put where
-- an earlier frame has its paper, for frames whose crease graph grew.
placement :: Spec
placement = describe "placing a later frame's vertices on an earlier frame" $ do
  -- (a) 05 L2's batch creased at rest on the diagonal pattern: no paper
  -- moves. Vertices 4, 5 and 6 lie on edges of the earlier frame and are
  -- read along them; vertex 7 lies on none, at (1/4, 1/4) inside face
  -- [0, 1, 3], and is placed through that face's map. Exact, since every
  -- number is a quarter or a half. Red if an added vertex were looked for
  -- only in a face: 'insideRing' calls a point on a face's edge outside it, so
  -- vertices 4, 5 and 6 would be refused as off the paper.
  it "places the at-rest batch exactly, on edges and inside a face" $ do
    cp <- diagonalPattern
    later <- right (fst <$> creaseAllAlongWith AtRest [(V2 0 0.5, V2 0.5 0, Valley), (V2 0 0, V2 1 1, Mountain)] cp)
    placeOn cp later
      `shouldBe` Right [V3 0 0 0, V3 1 0 0, V3 1 1 0, V3 0 1 0, V3 0 0.5 0, V3 0.5 0 0, V3 0.5 0.5 0, V3 0.25 0.25 0]

  -- (b) The earlier frame is the diagonal pattern folded on its diagonal,
  -- material points written in; the later frame creases the pattern at rest
  -- along (1/2, 1)-(1, 1/2) and the other diagonal. The vertex added at
  -- material (3/4, 3/4) is in the face the fold turned, which lies over the
  -- held face, so it is placed at (1/4, 1/4). Red if the map of the face
  -- held still, the identity, placed it at (3/4, 3/4). Vertices 4, 5 and 6
  -- are read along edges as the folded frame has them: material (1/2, 1)
  -- lands at (0, 1/2). Red if an edge vertex kept its place on the sheet.
  it "places an added vertex where the fold turned its face" $ do
    (earlier, later) <- foldedPair
    placed <- right (placeOn earlier later)
    earlierAt <- right (frameVertices earlier)
    take 4 placed `shouldBe` earlierAt
    farFrom (drop 4 placed) [V3 0 0.5 0, V3 0.5 0 0, V3 0.5 0.5 0, V3 0.25 0.25 0] `shouldBe` []

  -- The same folded frame recording no faces, so that they are traced on its
  -- material points, though its class says it is a folded form. Red if the
  -- trace read that class, which refuses the sheet as folded.
  it "traces a folded frame's faces on the sheet when it records none" $ do
    (earlier, later) <- foldedPair
    let faceless = earlier {facesVertices = [], faceOrders = [], frameClasses = ["foldedForm"]}
    placeOn faceless later `shouldBe` placeOn earlier later

  -- An L-shaped face, which two creases leave where they meet end to end: the
  -- earlier frame, hand-written with no faces so that they are traced, is a
  -- unit square creased along (0, 1/2)-(3/10, 1/2)-(3/10, 1). The later frame
  -- creases it at rest along x = 9/20 and y = 3/4 from (3/10, 3/4), which
  -- cross at (9/20, 3/4) in the arm of the L, on no earlier edge. Red if the
  -- face holding it were found by a half-plane test, which calls the arm
  -- outside the L and refuses the vertex as off the paper.
  -- Vertices 7, 8 and 10 are read along earlier edges at 9/20, 11/14 and
  -- 3/4 of the way along, not halfway. Red if an edge were read from its
  -- other end, which puts them at (11/20, 0), (17/20, 1) and (1, 1/4).
  it "places a vertex in the arm of a face that is not convex" $ do
    later <- right (fst <$> creaseAllAlongWith AtRest [(V2 0.45 0, V2 0.45 1, Valley), (V2 0.3 0.75, V2 1 0.75, Valley)] lPattern)
    placed <- right (placeOn lPattern later)
    farFrom placed (sheetOf (verticesCoords lPattern) <> [V3 0.45 0 0, V3 0.45 1 0, V3 0.3 0.75 0, V3 1 0.75 0, V3 0.45 0.75 0]) `shouldBe` []

  -- An earlier frame whose diagonals cross with no vertex there, recording no
  -- faces: tracing cuts both at (1/2, 1/2), a corner of every traced face that
  -- the frame does not have, placed along the diagonal it lies on. The later
  -- frame adds two creases crossing at (3/4, 1/2), inside a traced face and on
  -- no earlier edge. Red if a traced corner were looked up only among the
  -- earlier frame's vertices: every face would be dropped and the vertex
  -- refused as off the paper.
  it "places a vertex in a traced face with a corner where two creases cross" $ do
    later <- right (fst <$> creaseAllAlongWith AtRest [(V2 1 0.25, V2 0.625 0.625, Valley), (V2 1 0.75, V2 0.625 0.375, Valley)] crossedPattern)
    placed <- right (placeOn crossedPattern later)
    drop 9 placed `shouldBe` [V3 0.75 0.5 0]

  -- examples/crease-stops.fold has a crease that ends at (1/2, 1/4), in the
  -- middle of the paper, so its faces cannot be traced. A vertex on one of
  -- its edges needs no face, and a pair that adds none needs nothing at all,
  -- so both are placed. Red if the faces were worked out before any vertex
  -- needed them, which refuses both.
  it "places what needs no face on a frame whose faces cannot be traced" $ do
    stops <- fixtureFrame "examples/crease-stops.fold"
    stopsAt <- right (frameVertices stops)
    across <- right (fst <$> creaseAllAlongWith AtRest [(V2 0 0.25, V2 1 0.25, Valley)] stops)
    placeOn stops across `shouldBe` Right (stopsAt <> [V3 0 0.25 0, V3 1 0.25 0])
    closed <- right (fst <$> creaseAllAlongWith AtRest [(V2 0.5 0.25, V2 0.5 0.5, Valley)] stops)
    placeOn stops closed `shouldBe` Right stopsAt

  -- Each refusal, from a named input. Red if a frame broken that way were
  -- placed anyway, or refused for the wrong reason.
  describe "what it refuses" $ do
    it "refuses a frame whose paper's place on the sheet is not known, either one" $ do
      cp <- diagonalPattern
      folded <- right (foldFrame cp)
      placeOn folded cp `shouldBe` Left MaterialCoordinatesMissing
      placeOn cp folded `shouldBe` Left (InNextFrame MaterialCoordinatesMissing)

    it "refuses a later frame that does not begin with the earlier one's vertices" $ do
      cp <- diagonalPattern
      let swapped = cp {verticesCoords = drop 1 (take 2 (verticesCoords cp)) <> take 1 (verticesCoords cp) <> drop 2 (verticesCoords cp)}
      placeOn cp swapped `shouldBe` Left (VerticesNotAPrefix (VertexId 0))
      -- The L's first four vertices are the square's, so the square stops
      -- short of its vertex 4.
      placeOn lPattern cp `shouldBe` Left (VerticesNotAPrefix (VertexId 4))
      -- A vertex moved by a billionth, inside the hair 'toleranceOf' gives
      -- these points, is still not the same vertex: the prefix is compared
      -- number for number. Red if it were compared within a tolerance.
      placeOn cp cp {verticesCoords = [1e-9, 0] : drop 1 (verticesCoords cp)} `shouldBe` Left (VerticesNotAPrefix (VertexId 0))

    it "refuses an added vertex where the earlier frame has no paper" $ do
      cp <- diagonalPattern
      placeOn cp cp {verticesCoords = verticesCoords cp <> [[2, 2]]} `shouldBe` Left (AddedVertexOffPaper (VertexId 4))

    -- A vertex added inside a face of examples/crease-stops.fold needs the
    -- faces, which cannot be traced, and is refused for the reason tracing
    -- gives.
    it "refuses a vertex that needs faces the earlier frame cannot trace" $ do
      stops <- fixtureFrame "examples/crease-stops.fold"
      placeOn stops stops {verticesCoords = verticesCoords stops <> [[0.25, 0.75]]} `shouldBe` Left (VertexTooFewCreases (VertexId 9) 1)

    -- A frame that is not good FOLD is refused for its own fault, not blamed
    -- on its material points.
    it "passes on a refusal from reading the frame itself" $ do
      cp <- diagonalPattern
      let stray = cp {edgesVertices = edgesVertices cp <> [(VertexId 0, VertexId 9)], edgesAssignment = edgesAssignment cp <> [Valley], edgesFoldAngle = edgesFoldAngle cp <> [0]}
      placeOn stray cp `shouldBe` Left (VertexIndexOutOfRange (EdgeId 5) (VertexId 9) 4)

    it "refuses material points it cannot read, saying how" $ do
      cp <- diagonalPattern
      let withMaterial value = cp {frameExtras = KM.insert "senbazuru:material_coords" value (frameExtras cp)}
      placeOn (withMaterial (toJSON ("corners" :: String))) cp `shouldBe` Left MaterialCoordinatesUnreadable
      placeOn (withMaterial (toJSON [[0, 0], [1, 0], [1, 1 :: Double]])) cp `shouldBe` Left (MaterialCoordinatesCount 4 3)
      placeOn (withMaterial (toJSON [[0, 0], [1, 0, 0], [1, 1], [0, 1 :: Double]])) cp `shouldBe` Left (MaterialPointInvalid (VertexId 1))
      placeOn cp {verticesCoords = [0 / 0, 0] : drop 1 (verticesCoords cp)} cp `shouldBe` Left (VertexNotFinite (VertexId 0))
      -- The later frame's are the same refusals, said to be about it.
      placeOn cp (withMaterial (toJSON ("corners" :: String))) `shouldBe` Left (InNextFrame MaterialCoordinatesUnreadable)

-- | 05 L5's moves between two frames ('motionsAcross'), for frames whose
-- crease pattern grew as much as for frames whose did not.
growing :: Spec
growing = describe "the moves across two frames" $ do
  -- 06's A13 and L5's first row. Where the crease pattern did not grow,
  -- 'motionsAcross' is 'motionsBetween' and needs no material points: the
  -- quarter fold's frames have none after the first. Red if every pair were
  -- placed, which refuses the quarter fold's first pair as
  -- InNextFrame MaterialCoordinatesMissing and its second, and the folded
  -- diagonal pattern, as MaterialCoordinatesMissing.
  it "is the moves between two frames where the crease pattern did not grow" $ do
    quarter <- steps
    flaps <- mapM flapStates [(singleFlap, EdgeId 6, FaceId 1, 150), (singleFlap {edgesFoldAngle = replicate 7 0}, EdgeId 6, FaceId 1, 180), (touchingFlap, EdgeId 8, FaceId 1, 90), (alignedFlap, EdgeId 8, FaceId 1, 90)]
    cp <- diagonalPattern
    folded <- right (foldFrame cp)
    let pairs = consecutive quarter <> concatMap consecutive flaps <> [(folded, cp)]
    length pairs `shouldBe` 2 + 4 * 3 + 1
    [motionsAcross b a | (b, a) <- pairs] `shouldBe` [motionsBetween b a | (b, a) <- pairs]
    map (fmap length . uncurry motionsBetween) pairs `shouldBe` replicate (length pairs) (Right 1)

  -- (b), the folded diagonal pattern against it creased at rest: the face
  -- the fold turned comes back, moving from (2/7, 2/7) to (5/7, 5/7), and the
  -- faces moved are the later frame's. Red if the motion's start were read
  -- where the later frame has the paper, which finds nothing moved, or if the
  -- faces were the earlier frame's, which moves face 1 alone, from (1/3, 1/3).
  -- Reversed, the later frame does not begin with the earlier one's vertices.
  it "finds the paper the fold turned coming back, between frames whose pattern grew" $ do
    (earlier, later) <- foldedPair
    case motionsAcross earlier later of
      Right [m] -> do
        (motionFaces m, motionCreases m) `shouldBe` ([FaceId 1, FaceId 2, FaceId 3, FaceId 4], [])
        farFrom [motionFrom m, motionTo m] [V3 (2 / 7) (2 / 7) 0, V3 (5 / 7) (5 / 7) 0] `shouldBe` []
      other -> expectationFailure ("expected one motion, got " <> show other)
    motionsAcross later earlier `shouldBe` Left (VerticesNotAPrefix (VertexId 4))

  -- L2's batch creased at rest: the pattern grew and no paper moved. Red if
  -- the pair went to 'motionsBetween', which refuses it for differing.
  it "finds nothing moved where creasing at rest grew the pattern" $ do
    cp <- diagonalPattern
    later <- right (fst <$> creaseAllAlongWith AtRest [(V2 0 0.5, V2 0.5 0, Valley), (V2 0 0, V2 1 1, Mountain)] cp)
    motionsAcross cp later `shouldBe` Right []
    motionsBetween cp later `shouldBe` Left (FramesDiffer "vertices_coords" 4 8)

  -- R-05-19's creases: the diagonal pattern flat, against it creased along
  -- the other diagonal and folded on the first. The old diagonal, cut in two
  -- by the new crease, is the later frame's edges 4 and 5, and changed from 0
  -- to the fold's angle; the new diagonal is edges 6 and 7, at rest, and one
  -- of them lies on the moving faces' rings. Red if angles were compared
  -- edge by id, which lists edge 4 alone, since the earlier frame has no edge
  -- 5, or if a new edge counted as changed, which lists edge 7 as well.
  it "lists the earlier creases whose angle changed, and never a new one" $ do
    cp <- diagonalPattern
    creased <- right (fst <$> creaseAllAlongWith AtRest [(V2 0 0, V2 1 1, Mountain)] cp)
    later <- right (foldFrameWith creased) >>= \f -> materialFrame <$> right (surfaceFromFolded f)
    case motionsAcross cp {edgesFoldAngle = replicate 5 0} later of
      Right [m] -> do
        (motionFaces m, motionCreases m) `shouldBe` ([FaceId 1, FaceId 2], [EdgeId 4, EdgeId 5])
        farFrom [motionFrom m, motionTo m] [V3 (2 / 3) (2 / 3) 0, V3 (1 / 3) (1 / 3) 0] `shouldBe` []
      other -> expectationFailure ("expected one motion, got " <> show other)

  -- An edge whose angle either frame leaves unrecorded did not change, as
  -- 'motionsBetween' reads a frame that records none: the same pair, with each
  -- frame's angles taken away in turn. Red if a missing angle were read as 0,
  -- which lists the old diagonal's halves.
  it "lists no crease where a frame records no angles" $ do
    cp <- diagonalPattern
    creased <- right (fst <$> creaseAllAlongWith AtRest [(V2 0 0, V2 1 1, Mountain)] cp)
    later <- right (foldFrameWith creased) >>= \f -> materialFrame <$> right (surfaceFromFolded f)
    map motionCreases <$> motionsAcross cp {edgesFoldAngle = []} later `shouldBe` Right [[]]
    map motionCreases <$> motionsAcross cp later {edgesFoldAngle = []} `shouldBe` Right [[]]

  -- Each step of two runs whose crease patterns grow: the motion found
  -- between the state before the step and the state it writes, against the
  -- one found between its first record's before and its last record's after,
  -- each shown as the reader sees it ('displayedFrame'), whose crease pattern
  -- is the same. The ends agree, at the hand-worked points. Red if the start
  -- were read where the later frame has the paper, which finds nothing moved;
  -- if the faces were the earlier frame's; or if a turn of the whole model
  -- went unrecognised, which gives a turn-over a motion. The fold of each run's
  -- second step is made along a crease it adds, now at a flat fold's angle, so
  -- its creases are listed as none. Red if a crease the later frame adds were
  -- compared with an angle of 0.
  it "finds each step's motion where its own records find it" $
    forM_ [(creasedTwice, [[], [(V3 (2 / 7) (3 / 7) 0, V3 (5 / 7) (3 / 7) 0)]]), (turnedEachStep, [[], [(V3 0.5 0.5 0, V3 0.5 (2 / 7) 0)]])] $ \(source, expected) -> do
      run <- right (checkSequence source >>= runSequence defaultRunSettings M.empty . elaborate)
      states <- right (writtenStates run)
      forM_ (zip3 [1 ..] (consecutive (map stateFrame states)) expected) $ \(k, (b, a), want) -> do
        fromStates <- right (motionsAcross b a)
        fromRecords <- case [r | r <- runRecords run, recordStep r == k] of
          first' : rest ->
            let final = last (first' : rest)
             in right (motionsBetween (displayedFrame (recordBefore first') (displayBefore first')) (displayedFrame (recordAfter final) (displayAfter final)))
          [] -> fail ("no record for step " <> show k)
        (k, length fromStates, length fromRecords) `shouldBe` (k, length want, length want)
        (k, farFrom (concatMap ends fromStates) (concatMap pair want), farFrom (concatMap ends fromRecords) (concatMap pair want)) `shouldBe` (k, [], [])
        (k, map motionCreases fromStates) `shouldBe` (k, map (const []) want)

  -- Two flaps folded onto the middle of a strip of three squares while a
  -- crease grows across the middle: two motions, each listing the hinge it
  -- turned about and not the other's, as 'motionsBetween' does for the same
  -- fold without the crease. Red if a group listed every crease that changed,
  -- wherever it lies.
  it "gives each group its own motion and its own creases, where the pattern grew" $
    motionsAcross stripFlat stripFolded
      `shouldBe` Right
        [ Motion [FaceId 0] [EdgeId 1] (V3 0.5 0.5 0) (V3 1.5 0.5 0),
          Motion [FaceId 3] [EdgeId 2] (V3 2.5 0.5 0) (V3 1.5 0.5 0)
        ]

  -- A grown pair is refused for what placing it refuses. Red if the later
  -- frame's refusal were not said to be about it, or if a pair that shrank
  -- were sent to 'motionsBetween', which refuses it for differing.
  it "refuses a grown pair as placing it refuses" $ do
    cp <- diagonalPattern
    l2 <- right (fst <$> creaseAllAlongWith AtRest [(V2 0 0.5, V2 0.5 0, Valley), (V2 0 0, V2 1 1, Mountain)] cp)
    folded <- right (foldFrame l2)
    motionsAcross cp folded `shouldBe` Left (InNextFrame MaterialCoordinatesMissing)
    motionsAcross l2 cp `shouldBe` Left (VerticesNotAPrefix (VertexId 4))

-- | The four states a checked turn of one flap goes through, as FlapSpec draws
-- them, each with its material points.
flapStates :: (Frame, EdgeId, FaceId, Double) -> IO [Frame]
flapStates (sheet, edge, face, angle) = do
  start <- right (foldFrameWith sheet)
  motion <- right (prepareFlap edge face angle start >>= checkFlap defaultSweepSettings)
  states <- right (traverse (flapAt motion) [0, 1 / 3, 2 / 3, 1])
  pure (map materialFrame states)

-- | A strip of three unit squares, flat, its two hinges valleys at rest:
-- faces 0, 1 and 2 from the left.
stripFlat :: Frame
stripFlat =
  emptyFrame
    { verticesCoords = [[0, 0], [0, 1], [1, 0], [1, 1], [2, 0], [2, 1], [3, 0], [3, 1]],
      edgesVertices = [(VertexId a, VertexId b) | (a, b) <- [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (2, 4), (4, 6), (1, 3), (3, 5), (5, 7)]],
      edgesAssignment = [Border, Valley, Valley] <> replicate 7 Border,
      edgesFoldAngle = replicate 10 0,
      facesVertices = [map VertexId [0, 2, 3, 1], map VertexId [2, 4, 5, 3], map VertexId [4, 6, 7, 5]],
      frameClasses = ["creasePattern"]
    }

-- | The strip with both outer squares folded in onto the middle one, and a
-- crease added across the middle, from (3/2, 0) to (3/2, 1), at rest: the
-- strip's vertices first, then the crease's two, each with its point on the
-- sheet. Faces 0 and 3 are the flaps.
stripFolded :: Frame
stripFolded =
  emptyFrame
    { verticesCoords = [[2, 0], [2, 1], [1, 0], [1, 1], [2, 0], [2, 1], [1, 0], [1, 1], [1.5, 0], [1.5, 1]],
      edgesVertices = [(VertexId a, VertexId b) | (a, b) <- [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (2, 8), (8, 4), (4, 6), (1, 3), (3, 9), (9, 5), (5, 7), (8, 9)]],
      edgesAssignment = [Border, Valley, Valley] <> replicate 9 Border <> [Valley],
      edgesFoldAngle = [0, 180, 180] <> replicate 10 0,
      facesVertices = [map VertexId [0, 2, 3, 1], map VertexId [2, 8, 9, 3], map VertexId [8, 4, 5, 9], map VertexId [4, 6, 7, 5]],
      frameClasses = ["foldedForm"],
      frameExtras = KM.singleton "senbazuru:material_coords" (toJSON ([[0, 0], [0, 1], [1, 0], [1, 1], [2, 0], [2, 1], [3, 0], [3, 1], [1.5, 0], [1.5, 1]] :: [[Double]]))
    }

consecutive :: [a] -> [(a, a)]
consecutive xs = zip xs (drop 1 xs)

ends :: Motion -> [V3]
ends m = [motionFrom m, motionTo m]

pair :: (V3, V3) -> [V3]
pair (a, b) = [a, b]

-- | A plain square pre-creased on a diagonal and turned over, then folded in
-- half along the line joining its west and east midpoints and turned over
-- again, anchored at (3/4, 1/4) as 'creasedTwice' is. Each step ends with a
-- turn of the whole model, and each adds creases.
turnedEachStep :: Sequence
turnedEachStep = sequenceOf (header "A square turned over at each step" sheetSquare (Just (at (3 / 4) (1 / 4)))) $ do
  step_ "Crease the diagonal, and turn the paper over." $ do
    move (FoldAndUnfold ValleyFold (Segment (CornerOf SouthWest) (CornerOf NorthEast)) FlapOfFirstArgument (Just (CornerOf NorthWest)))
    Build.turnOver LeftRight
  step_ "Fold the top half down, and turn the paper over." $ do
    move (Fold ValleyFold ToFlat (Segment (MidpointOfEdge West) (MidpointOfEdge East)) FlapOfFirstArgument (Just (CornerOf NorthEast)))
    Build.turnOver LeftRight

-- | @examples/diagonal-cp.fold@: a unit square with one valley diagonal, from
-- (0, 1) to (1, 0), and its two faces.
diagonalPattern :: IO Frame
diagonalPattern = fixtureFrame "examples/diagonal-cp.fold"

fixtureFrame :: FilePath -> IO Frame
fixtureFrame path = do
  bytes <- BS.readFile path
  either (fail . ("decode failed: " <>)) (pure . keyFrame) (decodeFoldFile bytes)

-- | Pair (b): the diagonal pattern folded on its diagonal, material points
-- written in, and the pattern creased at rest along (1/2, 1)-(1, 1/2) and
-- the other diagonal.
foldedPair :: IO (Frame, Frame)
foldedPair = do
  cp <- diagonalPattern
  earlier <- right (foldFrameWith cp) >>= \folded -> materialFrame <$> right (surfaceFromFolded folded)
  later <- right (fst <$> creaseAllAlongWith AtRest [(V2 0.5 1, V2 1 0.5, Valley), (V2 0 0, V2 1 1, Mountain)] cp)
  pure (earlier, later)

-- | The indices at which two lists of points are not within 1e-12, and any
-- index one list has and the other does not. Not within rather than further
-- than, so that a point placed at NaN counts as far.
farFrom :: [V3] -> [V3] -> [Int]
farFrom placed expected =
  [i | (i, p, q) <- zip3 [0 ..] placed expected, not (near p q)]
    <> [min (length placed) (length expected) .. max (length placed) (length expected) - 1]
  where
    near p q = norm (p ^-^ q) < 1e-12

-- | Hand-written 2D coordinates, at z = 0.
sheetOf :: [[Double]] -> [V3]
sheetOf points = [V3 x y 0 | [x, y] <- points]

-- | A unit square with both diagonals as valleys and no vertex where they
-- cross, recording no faces.
crossedPattern :: Frame
crossedPattern =
  emptyFrame
    { verticesCoords = [[0, 0], [1, 0], [1, 1], [0, 1]],
      edgesVertices = [(VertexId a, VertexId b) | (a, b) <- [(0, 1), (1, 2), (2, 3), (3, 0), (0, 2), (1, 3)]],
      edgesAssignment = replicate 4 Border <> [Valley, Valley],
      edgesFoldAngle = replicate 6 0,
      frameClasses = ["creasePattern"]
    }

-- | A unit square creased along (0, 1/2)-(3/10, 1/2)-(3/10, 1), recording no
-- faces: the larger of its two is an L.
lPattern :: Frame
lPattern =
  emptyFrame
    { verticesCoords = [[0, 0], [1, 0], [1, 1], [0, 1], [0, 0.5], [0.3, 0.5], [0.3, 1]],
      edgesVertices = [(VertexId a, VertexId b) | (a, b) <- [(0, 1), (1, 2), (2, 6), (6, 3), (3, 4), (4, 0), (4, 5), (5, 6)]],
      edgesAssignment = replicate 6 Border <> [Valley, Valley],
      edgesFoldAngle = replicate 8 0,
      frameClasses = ["creasePattern"]
    }

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
