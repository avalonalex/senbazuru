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

import Data.List (nub)
import Data.Maybe (fromMaybe)
import Senbazuru.Diagram (Diagram (..), Shape (..), Stroke (..), diagramWithExtent, shapePoints)
import Senbazuru.Diagram.Style
  ( Notation (..),
    Theme (..),
    defaultTheme,
    layerStep,
    paperUnderside,
  )
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
import Senbazuru.Origami.Stacking (defaultBudget)
import Senbazuru.Origami.Step (Motion (..))
import Senbazuru.Render.Camera (View (..), bottomUp, defaultView, frontOn, isometric, topDown)
import Senbazuru.Render.CreasePattern
  ( creasePatternAuto,
    creasePatternFrom,
    defaultBasisFor,
    defaultNotationFor,
    withArrows,
  )
import Test.Hspec

-- | 'twoFaceSquare' with a face pointing at a vertex that does not exist.
broken :: Frame
broken = twoFaceSquare {facesVertices = [map VertexId [0, 1, 9]]}

-- | 'broken' with one corner lifted out of the plane, so that it is a folded
-- form with paper in the air.
brokenInTheAir :: Frame
brokenInTheAir = broken {verticesCoords = [[0, 0, 0], [1, 0, 0], [1, 1, 0.5], [0, 1, 0]]}

-- | The square folded along its diagonal: the top-left triangle has landed on
-- the bottom-right one, and no @faceOrders@ says which is in front.
foldedDiagonal :: Frame
foldedDiagonal =
  twoFaceSquare
    { frameClasses = ["foldedForm"],
      verticesCoords = [[0, 0], [1, 0], [1, 1], [1, 0]],
      edgesFoldAngle = [0, 0, 0, 0, 180]
    }

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
  map kind . diagramShapes <$> creasePatternFrom theme defaultBudget notation topDown fr
  where
    kind = \case
      Fill _ _ -> "fill"
      Polyline _ _ -> "line"
      Arrow _ -> "arrow"
      Label {} -> "label"
      -- Reported as whatever it wraps. Where a shape sits is a separate
      -- question from what it is, and the tests below that care ask about the
      -- displacements directly.
      Offset _ shape -> kind shape

-- | Close enough, for numbers that have been through a sine and a cosine.
nearly :: Double -> Double -> Bool
nearly a b = abs (a - b) < 1e-9

-- | The last element, if there is one.
lastOf :: [a] -> Maybe a
lastOf [] = Nothing
lastOf xs = Just (last xs)

spec :: Spec
spec = do
  describe "filling faces" $ do
    it "paints the paper before every line" $
      -- Not a detail of taste: SVG paints in document order, so a fill emitted
      -- after a crease would cover it. The two faces are one fill, because they
      -- tile one sheet in one colour and drawing them separately would leave a
      -- seam along the crease they share.
      shapeKinds defaultTheme CreasePatternNotation twoFaceSquare
        `shouldBe` Right ["fill", "line", "line", "line", "line", "line"]

    it "draws a flat folded form as what is visible of it" $
      -- The two triangles land on each other exactly, so only the top one is
      -- showing, and the five edges of the pattern land on the three sides of
      -- one triangle. The file says nothing about which triangle is in front;
      -- the answer comes from Senbazuru.Origami.Stacking.
      shapeKinds defaultTheme FoldedFormNotation foldedDiagonal
        `shouldBe` Right ["fill", "line", "line", "line"]

    it "shows the face that folded over last, seen from above" $ do
      -- Face 1 is the triangle that moved, over a valley, so it is on top, and
      -- the whole of it is what shows. Asserted on the fill's corners because
      -- the shapes carry no face ids.
      d <- either (fail . show) pure (creasePatternFrom defaultTheme defaultBudget FoldedFormNotation topDown foldedDiagonal)
      [rings | Fill _ rings <- diagramShapes d]
        `shouldBe` [[[V2 1 0, V2 1 1, V2 0 0]]]

    it "shows the other triangle from underneath" $ do
      -- The same model turned over: the buried face is the one on top now, and
      -- it presents the other side of the paper. Two things change together --
      -- which face shows, and which side of it -- and a view from below that
      -- got only one of them right would look plausible.
      d <- either (fail . show) pure (creasePatternFrom defaultTheme defaultBudget FoldedFormNotation bottomUp foldedDiagonal)
      -- Mirrored in x by the camera, which is what looking at the back of
      -- something does -- and which is why the ring comes out the other way
      -- round from the view above. A Fill means the union of its rings whatever
      -- their winding, and the backend is what turns them all one way.
      [rings | Fill _ rings <- diagramShapes d]
        `shouldBe` [[[V2 0 0, V2 (-1) 0, V2 (-1) 1]]]
      [c | Fill c _ <- diagramShapes d] `shouldBe` [paperUnderside]

    it "draws a flat folded form whose faces do not overlap as one sheet" $
      -- Two triangles tiling a square are declared folded. Nothing is on top of
      -- anything, both show the same side of the paper, and so they are one
      -- area of one colour with every crease still visible.
      shapeKinds defaultTheme FoldedFormNotation twoFaceSquare
        `shouldBe` Right (["fill"] <> replicate 5 "line")

    it "leaves a folded form in the air as a wireframe" $
      -- Ordering layers is only worked out for flat models. With paper still
      -- in the air and no faceOrders, a wireframe says only what is known.
      shapeKinds defaultTheme FoldedFormNotation (twoFaceSquare {verticesCoords = [[0, 0, 0], [1, 0, 0], [1, 1, 0.5], [0, 1, 0]]})
        `shouldBe` Right (replicate 5 "line")

    it "fills a folded form once the file supplies an ordering" $ do
      -- The half of layer ordering that is free: the file did the hard part.
      let stacked = twoFaceSquare {faceOrders = [FaceOrder (FaceId 1) (FaceId 0) Above]}
      shapeKinds defaultTheme FoldedFormNotation stacked
        `shouldBe` Right (["fill"] <> replicate 5 "line")

    it "refuses an ordering that puts a face in front of itself" $ do
      let impossible =
            twoFaceSquare
              { faceOrders =
                  [ FaceOrder (FaceId 1) (FaceId 0) Above,
                    FaceOrder (FaceId 0) (FaceId 1) Above
                  ]
              }
      shapeKinds defaultTheme FoldedFormNotation impossible
        `shouldBe` Left (ContradictoryStacking (FaceId 0) (FaceId 1))

    it "still refuses a circle when it is painting whole faces" $ do
      -- The same contradiction on a model with paper in the air, which no
      -- amount of region finding covers, so the faces are painted in the order
      -- paintOrder sorts them into -- and it will not invent one.
      let impossible =
            twoFaceSquare
              { verticesCoords = [[0, 0, 0], [1, 0, 0], [1, 1, 0.5], [0, 1, 0]],
                faceOrders =
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

    it "draws a folded form in the air whose faces are corrupt, having never looked" $
      -- With no ordering and none to be worked out there is nothing to fill,
      -- so the faces are never resolved. An earlier version validated them
      -- anyway and turned a file that had always rendered into a hard failure
      -- over data it was going to discard.
      shapeKinds defaultTheme FoldedFormNotation brokenInTheAir
        `shouldBe` Right (replicate 5 "line")

    it "rejects a corrupt face in a flat folded form, because it was going to fill it" $
      -- The same file lying flat has its layers worked out and its faces
      -- painted, so now the corrupt face is data that was going to be drawn.
      shapeKinds defaultTheme FoldedFormNotation broken
        `shouldBe` Left (FaceVertexOutOfRange (FaceId 0) (VertexId 9) 4)

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
        `shouldBe` Right ["fill", "line", "line", "line", "line", "line"]

  describe "the offset view" $ do
    let stepped d = defaultTheme {themeLayerOffset = d}
        drawn theme = creasePatternFrom theme defaultBudget FoldedFormNotation topDown
        offsetsOf d = [v | Offset v _ <- diagramShapes d]

    it "draws every face whole, buried or not" $
      -- Without an offset the two triangles land on each other exactly and the
      -- picture is one triangle -- correct, and no use to a reader who wants to
      -- know there are two. With one, both are drawn, each with its own three
      -- edges, and each layer's paper goes down before its lines so that it
      -- covers the layer beneath.
      --
      -- Eleven shapes, not eight: each sheet brings a fill and its three edges
      -- as part of the stack, and the top one brings its three edges a second
      -- time as the model itself, at the weight an ordinary picture would draw
      -- them. The buried sheet brings no such copy, because none of it shows.
      shapeKinds (stepped 4) FoldedFormNotation foldedDiagonal
        `shouldBe` Right (["fill"] <> replicate 3 "line" <> ["fill"] <> replicate 6 "line")

    it "draws the stack finer than the model standing on it" $ do
      -- The whole reason the offset view is legible on a model more than a
      -- couple of sheets deep. A dozen sheet edges within a few points of one
      -- another, all at the weight the model itself is drawn with, add up to a
      -- black band; drawn fine they read as the thickness of the paper.
      d <- either (fail . show) pure (drawn (stepped 4) foldedDiagonal)
      let widths = [strokeWidth st | Offset _ (Polyline st _) <- diagramShapes d]
          buried = themeBuriedWidth defaultTheme
      -- Six fine ones -- three per sheet, the stack -- and three at full
      -- weight, which are the model.
      length (filter (== buried) widths) `shouldBe` 6
      filter (/= buried) widths `shouldSatisfy` all (> buried)

    it "leaves the ordinary picture of the same frame alone" $ do
      -- The offset view reaches for hidden-line removal to tell the model from
      -- the stack, and reads a second, more finely cut list of the same edges
      -- to do it. The list an ordinary drawing uses is not that one, and this
      -- is what says so: turning the flag off has to give back exactly the
      -- picture it always did, down to how many strokes the outline is in.
      plain <- either (fail . show) pure (drawn defaultTheme foldedDiagonal)
      length (diagramShapes plain) `shouldBe` 4

    it "draws a crease shared by two layers once in each" $ do
      -- The diagonal bounds both triangles, and they are drawn a step apart, so
      -- one line cannot serve both. This is the whole of what the module header
      -- means by the one-polyline-per-crease pipeline having to change.
      d <- either (fail . show) pure (drawn (stepped 4) foldedDiagonal)
      let diagonals = [v | Offset v (Polyline _ [V2 0 0, V2 1 1]) <- diagramShapes d]
      length diagonals `shouldBe` 2
      nub diagonals `shouldBe` diagonals

    it "steps each layer one further than the one below it" $ do
      d <- either (fail . show) pure (drawn (stepped 4) foldedDiagonal)
      let step = fromMaybe (V2 0 0) (layerStep (stepped 4))
      -- Four shapes at rest and four a step along: the bottom triangle is drawn
      -- where the paper is, and the one on top of it is moved.
      nub (offsetsOf d) `shouldBe` [V2 0 0, step]

    it "leaves the page alone, so a stack opened out does not rescale it" $ do
      -- The displacement is in page units and never enters the extent. A page
      -- that grew to admit it would shrink the model every time the reader
      -- asked to see more of it.
      plain <- either (fail . show) pure (drawn defaultTheme foldedDiagonal)
      opened <- either (fail . show) pure (drawn (stepped 40) foldedDiagonal)
      diagramExtent opened `shouldBe` diagramExtent plain

    it "draws exactly the ordinary picture when it is zero" $ do
      -- Not merely a similar one: the offset view is a different picture
      -- altogether -- whole faces rather than visible regions -- so a theme
      -- asking for no offset must not take that path at all.
      plain <- either (fail . show) pure (drawn defaultTheme foldedDiagonal)
      off <- either (fail . show) pure (drawn (stepped 0) foldedDiagonal)
      off `shouldBe` plain

    it "has nothing to step apart in a crease pattern" $
      -- Its faces do not overlap, so every one of them is layer zero. The flag
      -- is harmless rather than special-cased.
      creasePatternFrom (stepped 4) defaultBudget CreasePatternNotation topDown twoFaceSquare
        `shouldBe` creasePatternFrom defaultTheme defaultBudget CreasePatternNotation topDown twoFaceSquare

    it "refuses a model whose layers have no single order" $ do
      -- Three faces in a circle: a real stacking, since no point is under all
      -- three, and one that cannot be drawn a layer at a time because there is
      -- no bottom layer to start from. The ordinary picture of a flat model
      -- draws it happily, which is why this is a refusal and not a fallback.
      let twist =
            twoFaceSquare
              { facesVertices = [map VertexId [0, 1, 2], map VertexId [0, 2, 3], map VertexId [0, 1, 3]],
                faceOrders =
                  [ FaceOrder (FaceId 1) (FaceId 0) Above,
                    FaceOrder (FaceId 2) (FaceId 1) Above,
                    FaceOrder (FaceId 0) (FaceId 2) Above
                  ]
              }
      shapeKinds (stepped 4) FoldedFormNotation twist
        `shouldBe` Left (ImpossibleStacking (FaceId 0))

  describe "turning the drawing" $ do
    it "turns every point of it, and nothing else" $ do
      -- The one place --rotate is wired in. Deleting the turn from basisFor
      -- left the whole suite green until this test existed: CameraSpec checks
      -- turnedBy on its own and never renders anything, and every other view
      -- here asks for no turn at all.
      let drawnWith view = creasePatternAuto defaultTheme defaultBudget view twoFaceSquare
      plain <- either (fail . show) pure (drawnWith defaultView)
      turned <- either (fail . show) pure (drawnWith (View Nothing pi))
      let points d = concatMap shapePoints (diagramShapes d)
          opposite (V2 x y) (V2 x' y') = nearly x (negate x') && nearly y (negate y')
      length (points turned) `shouldBe` length (points plain)
      and (zipWith opposite (points turned) (points plain)) `shouldBe` True

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
