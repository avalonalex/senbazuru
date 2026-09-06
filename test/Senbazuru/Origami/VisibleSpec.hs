-- |
-- Tests for what of a flat-folded model can be seen.
--
-- The assertions are areas and counts rather than coordinates, because that is
-- what can be checked against paper. Fold a square into quarters and one
-- quadrant of it is showing: a quarter of the sheet, bounded by four lines and
-- nothing else, however many layers went into it. Fold a strip in three and the
-- silhouette is the widest panel, with the narrow one peeping out beside it.
-- Both numbers come from the fixture's own coordinates, not from a previous
-- run of this code.
--
-- Two invariants are then checked on every fixture, including the ones nobody
-- could work out by hand. The visible parts must not overlap one another —
-- they are meant to tile the silhouette, and a gap or a double covering is how
-- a hidden-line algorithm goes wrong quietly. And every line drawn must be on
-- the edge of something visible, since a line floating over bare page is a
-- line the removal missed.
module Senbazuru.Origami.VisibleSpec (spec) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.List (sort, tails)
import Senbazuru.Fold.Load (decodeFoldFile)
import Senbazuru.Fold.Query (FoldError (..), frameFaces)
import Senbazuru.Fold.Types (Assignment (..), FaceOrder, Frame, keyFrame)
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (clipConvex, cross2, signedArea)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Flat (FlatError (..))
import Senbazuru.Origami.Folding (foldFrame)
import Senbazuru.Origami.Layers (paintOrder)
import Senbazuru.Origami.Stacking (solveStacking)
import Senbazuru.Origami.Visible
import Test.Hspec

-- | The key frame of a fixture, as the file gives it.
fixture :: String -> IO Frame
fixture name = do
  bytes <- BS.readFile ("test/fixtures/" <> name <> ".fold")
  case decodeFoldFile bytes of
    Left err -> fail ("decode failed: " <> err)
    Right f -> pure (keyFrame f)

-- | A crease-pattern fixture, folded along its own angles.
foldedFixture :: String -> IO Frame
foldedFixture name = do
  fr <- fixture name
  case foldFrame fr of
    Left err -> fail ("fold failed: " <> show err)
    Right folded -> pure folded

-- | The layer order senbazuru works out for a folded frame.
orders :: Frame -> IO [FaceOrder]
orders fr = case solveStacking fr of
  Left err -> fail ("stacking failed: " <> show err)
  Right os -> pure os

-- | A folded fixture, its layers solved, seen from the given side.
seen :: Bool -> String -> IO VisibleForm
seen fromAbove name = do
  folded <- foldedFixture name
  os <- orders folded
  case visibleForm fromAbove folded os of
    Left err -> fail ("visible failed: " <> show err)
    Right v -> pure v

flatten :: V3 -> V2
flatten (V3 x y _) = V2 x y

-- | Every visible piece of paper, as a ring in the plane.
pieces :: VisibleForm -> [[V2]]
pieces v = [map flatten piece | r <- formRegions v, piece <- regionPieces r]

-- | How much paper is showing.
visibleArea :: VisibleForm -> Double
visibleArea = sum . map (abs . signedArea) . pieces

-- | The area of one region.
areaOf :: Region -> Double
areaOf r = sum [abs (signedArea (map flatten piece)) | piece <- regionPieces r]

-- | Close enough, for numbers that came out of a folding simulation.
near :: Double -> Double -> Bool
near a b = abs (a - b) < 1e-9

-- | How far outside a convex ring a point is, and zero if it is inside or on
-- the boundary.
--
-- Zero-length edges are skipped: a ring can carry one where a clip passed
-- exactly through a corner, and the direction it would give is noise.
howFarOutside :: [V2] -> V2 -> Double
howFarOutside ring p =
  maximum
    ( 0
        : [ negate (cross2 (b ^-^ a) (p ^-^ a)) / norm (b ^-^ a)
            | (a, b) <- zip ring (drop 1 ring <> take 1 ring),
              norm (b ^-^ a) > 1e-12
          ]
    )

-- | Every flat-folded fixture, and both sides of each.
everyFlatFixture :: [(String, Bool)]
everyFlatFixture =
  [ (name, side)
    | name <- ["quarter-fold", "letter-fold", "thirds-pinwheel", "grid-2x2-d1", "kabuto", "crane"],
      side <- [True, False]
  ]

sideName :: Bool -> String
sideName fromAbove = if fromAbove then "from above" else "from below"

spec :: Spec
spec = do
  describe "coincident layers" $ do
    it "shows the quarter fold as one region, a quarter of the sheet" $ do
      -- All four faces land on the same quadrant, so three of them are hidden
      -- completely and the fourth is showing whole. The unit square's quadrant
      -- is 0.25, and no arithmetic in the fixture says so -- it is what folding
      -- a unit square twice does.
      v <- seen True "quarter-fold"
      map areaOf (formRegions v) `shouldSatisfy` all (near 0.25)
      length (formRegions v) `shouldBe` 1
      length (pieces v) `shouldBe` 1

    it "draws only the outline of the quarter fold" $ do
      -- Eight border edges and four creases went in. Two sides of the quadrant
      -- are the edge of the paper, with two coincident border edges each; two
      -- are folds. Nothing is left over to draw inside.
      v <- seen True "quarter-fold"
      sort (map visibleAssignment (formEdges v)) `shouldBe` [Border, Border, Mountain, Valley]

  describe "a layer covering another" $ do
    it "shows the long panel of the letter fold covering the short ones" $ do
      -- The strip is 1 wide with panels of 0.3, 0.2 and 0.5, folded to a
      -- silhouette 0.6 wide and 1 tall. The long panel takes 0.5 of that and
      -- the first panel's uncovered strip the remaining 0.1; the middle panel
      -- is buried.
      v <- seen True "letter-fold"
      sort (map areaOf (formRegions v)) `shouldSatisfy` \as ->
        length as == 2 && and (zipWith near as [0.1, 0.5])
      visibleArea v `shouldSatisfy` near 0.6

    it "hides the crease the long panel lies over" $ do
      -- Both creases of the letter fold end up inside the silhouette, and only
      -- one of them is still on the surface. Drawing the other is what a
      -- wireframe does and what this is for.
      v <- seen True "letter-fold"
      filter (`elem` [Mountain, Valley]) (map visibleAssignment (formEdges v))
        `shouldBe` [Mountain]

  describe "a twist" $ do
    forM_ ["thirds-pinwheel", "grid-2x2-d1"] $ \name ->
      it ("draws " <> name <> ", whose layers stack in a circle") $ do
        -- The flaps of a twist lie A over B over C over A, which is a valid
        -- stacking with no point under all three of them at once. There is no
        -- order to paint whole faces in, and 'paintOrder' refuses to invent
        -- one; there is still a picture, and this is it.
        folded <- foldedFixture name
        os <- orders folded
        faces <- either (fail . show) pure (frameFaces folded)
        paintOrder (V3 0 0 1) faces os `shouldSatisfy` \case
          Left (ImpossibleStacking _) -> True
          _ -> False
        v <- seen True name
        formRegions v `shouldSatisfy` (not . null)
        formEdges v `shouldSatisfy` (not . null)

  describe "the two sides of the paper" $ do
    it "turns the letter fold over to show the back of both panels" $ do
      -- Neither panel was flipped an odd number of times, so from above both
      -- show the side the crease pattern was drawn on, and from below both
      -- show the other one.
      above <- seen True "letter-fold"
      below <- seen False "letter-fold"
      map regionTopSide (formRegions above) `shouldBe` [True, True]
      map regionTopSide (formRegions below) `shouldBe` [False, False]

    it "sees the same silhouette from either side" $ do
      -- A different set of faces is on top, and the outline they add up to is
      -- the same paper: a model has one shadow.
      forM_ ["quarter-fold", "letter-fold", "thirds-pinwheel", "kabuto", "crane"] $ \name -> do
        above <- seen True name
        below <- seen False name
        visibleArea above `shouldSatisfy` near (visibleArea below)

  describe "every fixture" $ do
    forM_ everyFlatFixture $ \(name, side) -> do
      it ("tiles " <> name <> " " <> sideName side <> " without overlaps") $ do
        v <- seen side name
        let worst =
              maximum
                (0 : [abs (signedArea (clipConvex p q)) | (p : rest) <- tails (pieces v), q <- rest])
        worst `shouldSatisfy` (< 1e-9)

      it ("draws no line off the paper of " <> name <> " " <> sideName side) $ do
        -- Every stretch that survives is the boundary between two different
        -- things, so its middle has to lie on the edge of a visible piece.
        v <- seen side name
        let middles = [0.5 *^ (flatten (visibleFrom e) ^+^ flatten (visibleTo e)) | e <- formEdges v]
            stray m = minimum (map (`howFarOutside` m) (pieces v)) > 1e-9
        filter stray middles `shouldBe` []

      it ("stops no line in the middle of the paper of " <> name <> " " <> sideName side) $ do
        -- A line ends where the paper on its two sides stops differing, and
        -- what makes them stop differing is another edge -- so every end of
        -- every stretch has to be met by a second one, at its end or somewhere
        -- along it. This caught a real bug and is the reason it is here: a face
        -- whose edge lay exactly along a stretch was being dropped from the
        -- reckoning altogether, so the two sides agreed because neither could
        -- see it, and creases stopped dead in the middle of the crane.
        v <- seen side name
        let ends = concat [[flatten (visibleFrom e), flatten (visibleTo e)] | e <- formEdges v]
            met p = length (filter (samePoint p) ends) >= 2 || any (runsThrough p) (formEdges v)
            samePoint p q = norm (q ^-^ p) < 1e-9
            runsThrough p e =
              let (a, b) = (flatten (visibleFrom e), flatten (visibleTo e))
               in not (samePoint p a)
                    && not (samePoint p b)
                    && abs (cross2 (b ^-^ a) (p ^-^ a)) < 1e-9 * norm (b ^-^ a)
                    && dot (p ^-^ a) (b ^-^ a) > 0
                    && dot (p ^-^ b) (a ^-^ b) > 0
        filter (not . met) ends `shouldBe` []

  describe "what it declines" $ do
    it "declines a model with paper still in the air" $ do
      -- The rigidly folded square twist stands up out of the plane, so there
      -- is no one plane to cut into regions and no plane geometry to do it
      -- with. Declined rather than refused: the caller draws it as it always
      -- has, through "Senbazuru.Origami.Layers".
      fr <- fixture "squaretwist"
      visibleForm True fr [] `shouldSatisfy` \case
        Left (PaperInTheAir dz) -> dz > 0
        _ -> False
