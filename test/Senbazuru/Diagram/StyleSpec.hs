-- |
-- Tests for the line conventions.
--
-- The rule worth pinning is the one the camera broke without anyone noticing:
-- a folded form is drawn with solid edges, because the dashes mean "a fold
-- still to be made". The exact dash patterns are pinned by the golden files.
module Senbazuru.Diagram.StyleSpec (spec) where

import Control.Monad (forM_)
import Data.Maybe (mapMaybe)
import Senbazuru.Diagram (ArrowHead (..), ArrowPath (..), Dash (..), Stroke (..))
import Senbazuru.Diagram.Style
import Senbazuru.Fold.Types (Assignment (..))
import Senbazuru.Geometry (V2 (..), norm)
import Test.Hspec

spec :: Spec
spec = do
  describe "strokeFor" $ do
    it "never dashes an edge of a folded form" $
      map strokeDash (strokesUnder FoldedFormNotation) `shouldSatisfy` all (== Dash [])

    it "dashes exactly the mountains and valleys of a crease pattern" $
      forM_ everyAssignment $ \a ->
        case strokeFor defaultTheme CreasePatternNotation a of
          Nothing -> pure ()
          Just s -> (a, strokeDash s /= Dash []) `shouldBe` (a, a `elem` [Mountain, Valley])

    it "differs between the notations only in the dashes" $
      -- Same colours, same widths, same set of edges drawn at all. The
      -- folded-form picture of a frame is its crease-pattern picture with the
      -- instructions removed, nothing more.
      forM_ everyAssignment $ \a ->
        fmap undashed (strokeFor defaultTheme CreasePatternNotation a)
          `shouldBe` fmap undashed (strokeFor defaultTheme FoldedFormNotation a)

  describe "arrow heads" $ do
    -- 06's A2: an arrow nobody gave a kind keeps the head every page has
    -- drawn so far. Red if arrowFor set any other head.
    it "gives an arrow a solid head unless it is given a kind" $
      arrowHead plain `shouldBe` SolidHead

    -- Lang's conventions. Red if withKind gave any two kinds each other's
    -- heads.
    it "gives each kind the head a book draws it with" $
      [(k, arrowHead (withKind k plain)) | k <- [minBound .. maxBound]]
        `shouldBe` [(ValleyArrow, SolidHead), (MountainArrow, HollowHalfHead), (UnfoldArrow, HollowDoubleHead)]

    -- Red if a kind also moved the curve, or changed its ink or the head's
    -- length.
    it "changes nothing but the head" $
      forM_ [minBound .. maxBound] $ \k ->
        (k, (withKind k plain) {arrowHead = arrowHead plain}) `shouldBe` (k, plain)

  describe "themeLayers" $
    it "lays the paper flat in the default theme" $
      -- An offset view is a cutaway, asked for on purpose, and so is a fan. A
      -- drawing that moved its layers apart unasked would be saying the paper
      -- is somewhere it is not. Asked of the field, not of layerStep, which
      -- answers Nothing for OffsetBy 0 too.
      themeLayers defaultTheme `shouldBe` LaidFlat

  describe "towardDeeperPaper" $ do
    it "points down the page and to the left, at unit length" $ do
      -- Page y grows downwards, so down the page is positive.
      let V2 x y = towardDeeperPaper
      (x < 0, y > 0, x == negate y) `shouldBe` (True, True, True)
      abs (norm towardDeeperPaper - 1) `shouldSatisfy` (< 1e-15)

    it "has parts of sqrt 0.5, the bits the offset view was drawn with" $
      -- 1 / sqrt 2 is a different double, one unit in the last place lower,
      -- and a step built from it is not exactly as long as asked, which the
      -- test of a step's length below sees. No golden file sees it, so this
      -- is what keeps the offset view on the bits it has always been drawn
      -- with.
      towardDeeperPaper `shouldBe` V2 (negate (sqrt 0.5)) (sqrt 0.5)

  describe "layerStep" $ do
    it "is off in the default theme, and for an offset of zero" $ do
      layerStep defaultTheme `shouldBe` Nothing
      steppedBy 0 `shouldBe` Nothing

    it "steps against towardDeeperPaper, so the deeper paper ends up where a fan puts it" $
      -- The offset view moves the nearer layers away from the deeper ones; a
      -- fan moves the deeper corners along the direction. One constant, read
      -- both ways, so the two pictures cannot open a stack in different
      -- directions.
      steppedBy 1 `shouldBe` Just (let V2 x y = towardDeeperPaper in V2 (negate x) (negate y))

    it "steps by the distance asked for, measured on the page" $
      -- Not four points along each axis: four points apart, which is what
      -- anybody choosing a number means by it.
      fmap norm (steppedBy 4) `shouldBe` Just 4

    it "steps up the page and to the right" $ do
      -- Page y grows downwards, so up the page is negative. That sign is the
      -- one thing here worth a test of its own: everywhere else in senbazuru a
      -- positive y is up.
      fmap (\(V2 x _) -> x > 0) (steppedBy 4) `shouldBe` Just True
      fmap (\(V2 _ y) -> y < 0) (steppedBy 4) `shouldBe` Just True

    it "refuses a step that is not a length" $ do
      -- read for a Double accepts both, and formatNumber writes both as 0, so
      -- the alternative is every layer drawn at the page origin with nothing
      -- reporting a fault.
      steppedBy (0 / 0) `shouldBe` Nothing
      steppedBy (1 / 0) `shouldBe` Nothing
  where
    steppedBy d = layerStep defaultTheme {themeLayers = OffsetBy d}

    everyAssignment = [minBound .. maxBound] :: [Assignment]
    strokesUnder notation = mapMaybe (strokeFor defaultTheme notation) everyAssignment
    undashed s = s {strokeDash = Dash []}

-- | An arrow as 'arrowFor' makes one, across a unit square.
plain :: ArrowPath
plain = arrowFor defaultTheme (V2 0.25 0.5) (V2 0.75 0.5)
