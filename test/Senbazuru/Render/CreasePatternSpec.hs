-- |
-- Tests for the rendering policy that used to live in the executable.
--
-- 'defaultBasisFor' decides which way to look at geometry nobody has specified
-- a view for. It sat in @app\/@ originally, where the test suite cannot reach
-- it, and a bug went unnoticed for exactly that reason: the first version keyed
-- off @frame_classes@ and sheared every flat-folded model.
--
-- 'defaultNotationFor' decides whether the lines are instructions (a crease
-- pattern) or edges (a folded form). It is the one policy that /does/ consult
-- @frame_classes@, and the tests below say exactly when.
module Senbazuru.Render.CreasePatternSpec (spec) where

import Senbazuru.Diagram (Diagram (..), Shape (..), diagramWithExtent)
import Senbazuru.Diagram.Style (Notation (..), Theme (..), defaultTheme)
import Senbazuru.Fold.Query (FoldError (..))
import Senbazuru.Fold.Types
  ( Assignment (..),
    FaceId (..),
    FaceOrder (..),
    Frame (..),
    Stacking (..),
    VertexId (..),
    emptyFrame,
  )
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Step (Motion (..))
import Senbazuru.Render.Camera (frontOn, isometric, topDown)
import Senbazuru.Render.CreasePattern
  ( creasePatternFrom,
    defaultBasisFor,
    defaultNotationFor,
    withArrows,
  )
import Test.Hspec

-- | 'twoFaceSquare' with a face pointing at a vertex that does not exist.
broken :: Frame
broken = twoFaceSquare {facesVertices = [map VertexId [0, 1, 9]]}

-- | A unit square split into two triangles by a valley along the diagonal.
twoFaceSquare :: Frame
twoFaceSquare =
  emptyFrame
    { verticesCoords = [[0, 0], [1, 0], [1, 1], [0, 1]],
      edgesVertices =
        [ (VertexId 0, VertexId 1),
          (VertexId 1, VertexId 2),
          (VertexId 2, VertexId 3),
          (VertexId 3, VertexId 0),
          (VertexId 0, VertexId 2)
        ],
      edgesAssignment = [Border, Border, Border, Border, Valley],
      facesVertices = [map VertexId [0, 1, 2], map VertexId [0, 2, 3]]
    }

-- | The shapes of a rendered frame, or the error, as a list of tags in order.
shapeKinds :: Theme -> Notation -> Frame -> Either FoldError [String]
shapeKinds theme notation fr =
  map kind . diagramShapes <$> creasePatternFrom theme notation topDown fr
  where
    kind = \case
      Polygon _ _ -> "fill"
      Polyline _ _ -> "line"
      Arrow _ -> "arrow"

-- | The last element, if there is one.
lastOf :: [a] -> Maybe a
lastOf [] = Nothing
lastOf xs = Just (last xs)

spec :: Spec
spec = do
  describe "filling faces" $ do
    it "paints every face before every line" $
      -- Not a detail of taste: SVG paints in document order, so a fill emitted
      -- after a crease would cover it.
      shapeKinds defaultTheme CreasePatternNotation twoFaceSquare
        `shouldBe` Right ["fill", "fill", "line", "line", "line", "line", "line"]

    it "leaves a folded form as a wireframe when nothing says which face is in front" $
      -- Its faces overlap, so drawing them in file order would be a confident
      -- picture of the wrong thing. A wireframe says only what is known.
      shapeKinds defaultTheme FoldedFormNotation twoFaceSquare
        `shouldBe` Right (replicate 5 "line")

    it "fills a folded form once the file supplies an ordering" $ do
      -- The half of layer ordering that is free: the file did the hard part.
      let stacked = twoFaceSquare {faceOrders = [FaceOrder (FaceId 1) (FaceId 0) Above]}
      shapeKinds defaultTheme FoldedFormNotation stacked
        `shouldBe` Right (["fill", "fill"] <> replicate 5 "line")

    it "refuses an ordering that puts a face in front of itself" $ do
      let impossible =
            twoFaceSquare
              { faceOrders =
                  [ FaceOrder (FaceId 1) (FaceId 0) Above,
                    FaceOrder (FaceId 0) (FaceId 1) Above
                  ]
              }
      shapeKinds defaultTheme FoldedFormNotation impossible
        `shouldBe` Left (ImpossibleStacking (FaceId 0))

    it "draws only lines when the theme has no paper" $
      shapeKinds (defaultTheme {themePaper = Nothing}) CreasePatternNotation twoFaceSquare
        `shouldBe` Right (replicate 5 "line")

    it "rejects a corrupt face when it was going to draw it" $
      shapeKinds defaultTheme CreasePatternNotation broken
        `shouldBe` Left (FaceVertexOutOfRange (FaceId 0) (VertexId 9) 4)

    it "draws a folded form whose faces are corrupt, having never looked" $
      -- With no ordering there is nothing to fill, so the faces are never
      -- resolved. An earlier version validated them anyway and turned a file
      -- that had always rendered into a hard failure over data it was going to
      -- discard.
      shapeKinds defaultTheme FoldedFormNotation broken
        `shouldBe` Right (replicate 5 "line")

    it "draws a wireframe whose faces are corrupt, for the same reason" $
      shapeKinds (defaultTheme {themePaper = Nothing}) CreasePatternNotation broken
        `shouldBe` Right (replicate 5 "line")

    it "fills a flat-folded model that declares no class -- a known limitation" $ do
      -- Pinned rather than fixed. A flat-folded model and a crease pattern have
      -- identical coordinates, so defaultNotationFor can only tell them apart by
      -- asking frame_classes, and a file that declares nothing has been drawn as
      -- a crease pattern since long before faces existed. Telling them apart for
      -- real means asking whether the faces overlap, which is layer ordering.
      -- See docs/notes/layer-ordering.md.
      let undeclared = twoFaceSquare {frameClasses = []}
      shapeKinds defaultTheme (defaultNotationFor [] flatSquare) undeclared
        `shouldBe` Right ["fill", "fill", "line", "line", "line", "line", "line"]

  describe "arrows" $ do
    let square = diagramWithExtent (Box (V2 0 0) (V2 1 1)) []
        motion a b = Motion {motionFaces = [], motionCreases = [], motionFrom = a, motionTo = b}
        arrowsIn = length . filter isArrow . diagramShapes
        isArrow = \case Arrow _ -> True; _ -> False

    it "adds one arrow per motion, after everything else" $ do
      let d = withArrows defaultTheme topDown [motion (V3 0.25 0.5 0) (V3 0.75 0.5 0)] square
      arrowsIn d `shouldBe` 1
      fmap isArrow (lastOf (diagramShapes d)) `shouldBe` Just True

    it "draws none for paper that moved without going anywhere on the page" $ do
      -- A model turned over, or a flap folded straight up and seen from above:
      -- the paper moved, and its two ends land on the same point. A book marks
      -- that with a loop or a pair of arrows and senbazuru has neither, so an
      -- arrow here would be given a direction by whatever the arithmetic
      -- happened to produce and would say something confident and untrue.
      let flip' = motion (V3 0.5 0.5 0) (V3 0.5 0.5 1)
      arrowsIn (withArrows defaultTheme topDown [flip'] square) `shouldBe` 0
      -- Seen from the side, the same motion is a real displacement.
      arrowsIn (withArrows defaultTheme frontOn [flip'] square) `shouldBe` 1

  describe "defaultBasisFor" $ do
    it "views a flat sheet from above" $
      defaultBasisFor flatSquare `shouldBe` topDown

    it "views something with relief isometrically" $
      defaultBasisFor withRelief `shouldBe` isometric

    it "views a FLAT-FOLDED model from above, not isometrically" $
      -- The case the first version got wrong. A folded form need not be 3D: the
      -- traditional crane folds flat, so its folded frame lies in a plane, and an
      -- isometric camera would shear a correct picture into a wrong one. Keying
      -- off frame_classes could not tell these apart; the coordinates can.
      defaultBasisFor flatFolded `shouldBe` topDown

    it "judges flatness relative to the sheet, not absolutely" $ do
      -- A thousandth of a unit of relief is nothing on a large sheet...
      defaultBasisFor [V3 0 0 0, V3 1000 1000 0, V3 500 500 0.001] `shouldBe` isometric
      -- ...and everything on a tiny one. Both are "0.001", so an absolute
      -- threshold would have to be wrong about one of them.
      defaultBasisFor [V3 0 0 0, V3 0.001 0.001 0, V3 0 0 0.001] `shouldBe` isometric

    it "has an answer for no vertices at all" $
      -- Rendering fails right afterwards with NoVertices; this must not throw
      -- first, or the error the user sees is the wrong one.
      defaultBasisFor [] `shouldBe` topDown

  describe "defaultNotationFor" $ do
    it "draws a flat frame that says nothing as a crease pattern" $
      -- The behaviour every version so far has had, kept for the many files
      -- that declare no class.
      defaultNotationFor [] flatSquare `shouldBe` CreasePatternNotation

    it "draws anything with relief as a folded form, classes or not" $ do
      -- A crease pattern is flat by definition, so relief settles the question
      -- before the class is consulted...
      defaultNotationFor [] withRelief `shouldBe` FoldedFormNotation
      -- ...even when the class disagrees. The coordinates are the paper; the
      -- class is a claim about it.
      defaultNotationFor ["creasePattern"] withRelief `shouldBe` FoldedFormNotation

    it "believes a flat frame that calls itself a folded form" $
      -- The flat-folded crane. Its coordinates look like any other flat sheet,
      -- so the class is the only thing that can say its edges are edges.
      defaultNotationFor ["foldedForm"] flatFolded `shouldBe` FoldedFormNotation

    it "draws a flat frame that calls itself a crease pattern as one" $
      defaultNotationFor ["creasePattern"] flatSquare `shouldBe` CreasePatternNotation

    it "has an answer for no vertices at all" $
      defaultNotationFor [] [] `shouldBe` CreasePatternNotation
  where
    flatSquare = [V3 0 0 0, V3 1 0 0, V3 1 1 0, V3 0 1 0]
    withRelief = [V3 0 0 0, V3 1 0 0, V3 1 1 0.5]
    flatFolded = [V3 0 0 0, V3 0.5 0 0, V3 0.5 0.5 0]
