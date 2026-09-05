-- |
-- Tests for folding a crease pattern into its folded form.
--
-- Three things need pinning and they need different kinds of test.
--
-- __Rigidity__ is a property: whatever the angles, no edge may change length.
-- It is stated over random angles on a two-face sheet, which has no interior
-- vertex and so folds for any angle at all.
--
-- __The sign convention__ is a pair of examples, because it is a convention and
-- there is nothing to generalise over: a valley lifts the moving face towards
-- the viewer and a mountain drops it away. Half of a folded model comes out
-- backwards if these are wrong, and nothing else in the suite would notice.
--
-- __Loop closure__ is what a spanning tree cannot see, so it gets examples on
-- both sides: a pattern whose angles close, folded; and the same pattern with
-- angles that cannot close, refused.
module Senbazuru.Origami.FoldingSpec (spec) where

import Data.ByteString qualified as BS
import Data.Either (fromRight)
import Senbazuru.Fold.Load (decodeFoldFile)
import Senbazuru.Fold.Query (FoldError (..), frameVertices)
import Senbazuru.Fold.Types
  ( Assignment (..),
    FaceId (..),
    Frame (..),
    VertexId (..),
    emptyFrame,
    keyFrame,
  )
import Senbazuru.Geometry.V3 (V3 (..), zSpan)
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Folding
import Test.Hspec
import Test.QuickCheck

-- | A unit square cut in two by a crease down the middle, with the given angle
-- in degrees on that crease.
--
-- No interior vertex, so there is no loop to close and every angle is
-- foldable. Face 0 is the left half and is the one held still.
halfSheet :: Assignment -> Double -> Frame
halfSheet assignment angle =
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
      edgesFoldAngle = replicate 6 0 <> [angle],
      facesVertices =
        [ map VertexId [0, 1, 4, 5],
          map VertexId [1, 2, 3, 4]
        ]
    }

-- | The frame's vertices as points.
--
-- Via 'frameVertices' rather than by pattern-matching @[x, y, z]@, because a
-- crease pattern writes two components per vertex and a folded form writes
-- three. Matching on three silently discards every vertex of the flat frame,
-- which makes all its edges zero-length and a rigidity test that compares
-- against them pass for the wrong reason.
vertices :: Frame -> [V3]
vertices = fromRight [] . frameVertices

-- | Every edge's length, in the order the frame lists them.
edgeLengths :: Frame -> [Double]
edgeLengths fr =
  [ norm (at a ^-^ at b)
    | (a, b) <- edgesVertices fr
  ]
  where
    at (VertexId i) = case drop i (vertices fr) of
      (p : _) -> p
      [] -> V3 0 0 0

foldOrFail :: Frame -> IO Frame
foldOrFail fr = case foldFrame fr of
  Left err -> fail ("fold failed: " <> show err)
  Right folded -> pure folded

loadFixture :: FilePath -> IO Frame
loadFixture path = do
  bytes <- BS.readFile path
  case decodeFoldFile bytes of
    Left err -> fail ("decode failed: " <> err)
    Right f -> pure (keyFrame f)

-- | Is this point in the quadrant the quarter fold collapses into?
--
-- Written over a list because that is what verticesCoords holds; anything that
-- is not a plane coordinate is not in the quadrant.
inTheQuadrant :: [Double] -> Bool
inTheQuadrant [x, y] = x >= 0.5 - 1e-9 && y <= 0.5 + 1e-9
inTheQuadrant _ = False

-- | Rounded, so that a coordinate landing on 6e-17 compares as the zero it is.
rounded :: Double -> Double
rounded x = fromIntegral (round (x * 1e9) :: Integer) / 1e9

spec :: Spec
spec = do
  describe "rigidity" $ do
    it "never changes an edge's length, at any angle" $
      -- What "rigid" means, and the property that catches a transposed matrix,
      -- a wrong axis, or a composition done in the wrong order. None of those
      -- would be obvious in a picture.
      forAll (choose (-180, 180)) $ \angle ->
        let flat = halfSheet Valley angle
         in case foldFrame flat of
              Left _ -> False
              Right folded ->
                and (zipWith (\a b -> abs (a - b) < 1e-9) (edgeLengths flat) (edgeLengths folded))

    it "leaves a pattern with every angle zero exactly where it was" $ do
      let flat = halfSheet Valley 0
      folded <- foldOrFail flat
      map (map rounded) (verticesCoords folded)
        `shouldBe` [[0, 0, 0], [0.5, 0, 0], [1, 0, 0], [1, 1, 0], [0.5, 1, 0], [0, 1, 0]]

  describe "reading the winding from the coordinates" $ do
    it "folds a clockwise face the same as a counterclockwise one" $ do
      -- The reason orientCcw exists. FOLD specifies counterclockwise and real
      -- editors emit clockwise; a winding taken on trust flips the sign of
      -- every fold across that face. Every fixture in this repo happens to be
      -- counterclockwise, so without this the reversal branch never runs and a
      -- regression that deleted it would keep the suite green.
      let ccw = halfSheet Valley 90
          cw = ccw {facesVertices = map reverse (facesVertices ccw)}
      folded <- foldOrFail ccw
      flipped <- foldOrFail cw
      verticesCoords flipped `shouldBe` verticesCoords folded

  describe "which way it turns" $ do
    it "lifts the moving face towards the viewer for a valley" $ do
      -- A valley opens towards you. The left half is held still in the plane,
      -- so the right half is the only thing that can rise.
      folded <- foldOrFail (halfSheet Valley 90)
      map (map rounded) (verticesCoords folded)
        `shouldBe` [[0, 0, 0], [0.5, 0, 0], [0.5, 0, 0.5], [0.5, 1, 0.5], [0.5, 1, 0], [0, 1, 0]]

    it "drops it away from the viewer for a mountain" $ do
      folded <- foldOrFail (halfSheet Mountain (-90))
      map (map rounded) (verticesCoords folded)
        `shouldBe` [[0, 0, 0], [0.5, 0, 0], [0.5, 0, -0.5], [0.5, 1, -0.5], [0.5, 1, 0], [0, 1, 0]]

    it "takes the angle from the assignment when the file gives none" $ do
      -- An assignment names a direction and not an amount, and the only amount
      -- consistent with naming no number is a flat fold.
      let noAngles = (halfSheet Mountain 0) {edgesFoldAngle = []}
      folded <- foldOrFail noAngles
      map (map rounded) (verticesCoords folded)
        `shouldBe` [[0, 0, 0], [0.5, 0, 0], [0, 0, 0], [0, 1, 0], [0.5, 1, 0], [0, 1, 0]]

  describe "folding a whole sheet flat" $ do
    it "folds the quarter fold into one quadrant, in the plane" $ do
      -- Four creases at a vertex, three mountains and one valley: the sheet
      -- ends up a quarter of its size with four layers, and every corner of the
      -- original stacks on one point.
      flat <- loadFixture "test/fixtures/quarter-fold.fold"
      folded <- foldOrFail flat
      let coords = map (map rounded) (verticesCoords folded)
      zSpan (vertices folded) `shouldSatisfy` (< 1e-9)
      -- The four corners of the square all land together.
      take 4 coords `shouldBe` replicate 4 [1, 0, 0]
      -- And the result occupies one quadrant.
      map (take 2) coords
        `shouldSatisfy` all inTheQuadrant

    it "folds the diagonal crease pattern into a triangle" $ do
      -- A square with a valley along the diagonal from (0,1) to (1,0). The
      -- triangle above that line folds onto the one below it, so the far corner
      -- (1,1) reflects onto (0,0) and the other three stay where they are.
      flat <- loadFixture "test/fixtures/diagonal-cp.fold"
      folded <- foldOrFail flat
      map (map rounded) (verticesCoords folded)
        `shouldBe` [[0, 0, 0], [1, 0, 0], [0, 0, 0], [0, 1, 0]]

    it "keeps the fold angles, which are the state" $ do
      -- Positions are derived from angles and not the other way round, so a
      -- folded frame that dropped them could not be folded further or unfolded.
      flat <- loadFixture "test/fixtures/quarter-fold.fold"
      folded <- foldOrFail flat
      edgesFoldAngle folded `shouldBe` edgesFoldAngle flat
      edgesVertices folded `shouldBe` edgesVertices flat

    it "says the result is a folded form" $ do
      -- Otherwise a flat-folded result would be drawn with crease-pattern
      -- dashes, which mean a fold still to be made.
      flat <- loadFixture "test/fixtures/quarter-fold.fold"
      folded <- foldOrFail flat
      frameClasses folded `shouldBe` ["foldedForm"]

  describe "loops the spanning tree cannot close" $ do
    it "refuses angles that tear the paper" $ do
      -- The same four creases folded to 90 degrees instead of 180. A tree
      -- reaches the last face by one path only, so it will happily produce
      -- coordinates for angles no sheet can adopt; this is the check that the
      -- faces meeting at a vertex are asked to agree.
      flat <- loadFixture "test/fixtures/quarter-fold.fold"
      let bent = flat {edgesFoldAngle = map (\a -> if a == 0 then 0 else 90) (edgesFoldAngle flat)}
      case foldFrame bent of
        Left (TornAt _ d) -> d `shouldSatisfy` (> 0.7)
        other -> expectationFailure ("expected a tear, got " <> show (fmap frameClasses other))

    it "does not mind a mountain and a valley swapped at 180 degrees" $ do
      -- Worth pinning because it is surprising: turning 180 degrees one way
      -- about a line and 180 the other way are the same motion, so at a flat
      -- fold the assignment does not move any paper. What it decides is which
      -- layer ends up on top, which is a separate question this does not
      -- answer. See docs/notes/layer-ordering.md.
      flat <- loadFixture "test/fixtures/quarter-fold.fold"
      let flipped = flat {edgesFoldAngle = map negate (edgesFoldAngle flat)}
      asFolded <- foldOrFail flat
      asFlipped <- foldOrFail flipped
      map (map rounded) (verticesCoords asFlipped)
        `shouldBe` map (map rounded) (verticesCoords asFolded)

  describe "patterns it will not fold" $ do
    it "refuses a sheet with no faces" $ do
      -- Creases alone do not say which pieces of paper move together.
      flat <- loadFixture "test/fixtures/unit-square.fold"
      foldFrame flat `shouldBe` Left NoFaces

    it "refuses something that is already folded" $ do
      flat <- loadFixture "test/fixtures/simple.fold"
      case foldFrame flat of
        Left (AlreadyFolded d) -> d `shouldSatisfy` (> 0)
        other -> expectationFailure ("expected a refusal, got " <> show (fmap frameClasses other))

    it "refuses to fold something it has already folded" $ do
      -- The trap this project keeps meeting: a flat-folded model has
      -- coordinates a crease pattern's cannot be told from, so only its class
      -- gives it away. Folding one a second time returns the crease pattern it
      -- came from, still labelled a folded form, with no complaint.
      flat <- loadFixture "test/fixtures/quarter-fold.fold"
      folded <- foldOrFail flat
      case foldFrame folded of
        Left (AlreadyFolded _) -> pure ()
        other -> expectationFailure ("expected a refusal, got " <> show (fmap frameClasses other))

    it "says 2D or 3D to match the coordinates it wrote" $ do
      -- FOLD's attribute describes exactly what folding changes, and this is
      -- the intended input to a FOLD writer, so a folded frame that kept its
      -- 2D while leaving the plane would write that contradiction to disk.
      let solid = (halfSheet Valley 90) {frameAttributes = ["2D"]}
      folded <- foldOrFail solid
      frameAttributes folded `shouldBe` ["3D"]
      stillFlat <- foldOrFail ((halfSheet Valley 180) {frameAttributes = ["3D"]})
      frameAttributes stillFlat `shouldBe` ["2D"]

    it "keeps the classes that are still true" $ do
      let labelled = (halfSheet Valley 90) {frameClasses = ["creasePattern", "singleModel"]}
      folded <- foldOrFail labelled
      frameClasses folded `shouldBe` ["foldedForm", "singleModel"]

    it "refuses angles that are a tenth of a degree short of closing" $ do
      -- Right angles written as 179.9 rather than 180 do not close, and the
      -- refusal says by how much. Small, but the tolerance deliberately does not
      -- try to judge how small is acceptable: the reported distance for this
      -- very file is 1.5e-6 or 1.7e-3 depending on which crease the spanning
      -- tree cut, so a threshold placed between them would be arbitrary. It
      -- admits arithmetic noise and leaves the judgement to the reader.
      flat <- loadFixture "test/fixtures/quarter-fold.fold"
      let rough = flat {edgesFoldAngle = map (\a -> if a == 0 then 0 else signum a * 179.9) (edgesFoldAngle flat)}
      case foldFrame rough of
        Left (TornAt _ d) -> d `shouldSatisfy` \x -> x > 1e-6 && x < 1e-2
        other -> expectationFailure ("expected a refusal, got " <> show (fmap frameClasses other))

    it "refuses an edges_foldAngle array of the wrong length" $ do
      -- Fold.Query says of the sibling array that "present but the wrong length
      -- is a corrupt file, not a default to paper over". An earlier version
      -- quietly substituted angles from the assignments, turning a truncated
      -- file into a different model that rendered without a word.
      let truncated = (halfSheet Valley 90) {edgesFoldAngle = [0, 0, 0]}
      foldFrame truncated
        `shouldBe` Left (FrameGeometry (ArrayLengthMismatch "edges_vertices" 7 "edges_foldAngle" 3))

    it "refuses a short edges_assignment when there are no angles either" $ do
      let truncated = (halfSheet Valley 90) {edgesFoldAngle = [], edgesAssignment = [Border, Border]}
      foldFrame truncated
        `shouldBe` Left (FrameGeometry (ArrayLengthMismatch "edges_vertices" 7 "edges_assignment" 2))

    it "refuses a fold angle that is not a number" $ do
      -- Every trig function of an infinity is NaN, a NaN matrix gives NaN
      -- coordinates, and formatNumber writes those as 0 -- so this would
      -- otherwise stack half the model on the origin in silence.
      let broken = (halfSheet Valley 90) {edgesFoldAngle = replicate 6 0 <> [1 / 0]}
      case foldFrame broken of
        Left (NonFiniteAngle _ _) -> pure ()
        other -> expectationFailure ("expected a refusal, got " <> show (fmap frameClasses other))

    it "refuses a face too thin to read an orientation from" $ do
      -- The shoelace sum of a sliver is a difference of large numbers, so its
      -- sign is rounding noise -- and that sign decides which way every fold
      -- across the face goes.
      let sliver =
            (halfSheet Valley 90)
              { verticesCoords = [[0, 0], [0.5, 0], [1, 0], [1, 1e-14], [0.5, 1e-14], [0, 1e-14]]
              }
      foldFrame sliver `shouldBe` Left (DegenerateFace (FaceId 0))

    it "refuses a face with no area" $ do
      let flatFace =
            (halfSheet Valley 90)
              { facesVertices = [map VertexId [0, 1, 2], map VertexId [1, 2, 3, 4]]
              }
      -- Vertices 0, 1 and 2 are collinear along y = 0, so that face has no
      -- orientation and there is no way to know which side the fold goes.
      foldFrame flatFace `shouldBe` Left (DegenerateFace (FaceId 0))

    it "refuses a crease with three faces along it" $ do
      let threeFaced =
            (halfSheet Valley 90)
              { facesVertices =
                  [ map VertexId [0, 1, 4, 5],
                    map VertexId [1, 2, 3, 4],
                    map VertexId [1, 2, 4]
                  ]
              }
      case foldFrame threeFaced of
        Left (NonManifoldEdge _ _ n) -> n `shouldBe` 3
        other -> expectationFailure ("expected a refusal, got " <> show (fmap frameClasses other))
