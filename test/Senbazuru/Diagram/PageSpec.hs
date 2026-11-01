-- |
-- Tests for fitting a page of captioned figures (PRDs\/06 §8).
--
-- The examples are the page S24 prototyped the method on, five of the blintz
-- run's captions under unit squares and a sixth figure half their size,
-- whose numbers C134 records; the property holds the fit to what the module
-- header claims for it on pages nobody wrote down: the page it settles on
-- fits, a larger scale would not, and a page it refuses fits at no scale it
-- could be asked about.
module Senbazuru.Diagram.PageSpec (spec) where

import Control.Monad (forM_)
import Data.Maybe (fromMaybe, isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Senbazuru.Diagram
import Senbazuru.Diagram.Layout
import Senbazuru.Diagram.Page
import Senbazuru.Diagram.Style (Theme (..), defaultTheme)
import Senbazuru.Explain (Explain (..))
import Senbazuru.Geometry
import Test.Hspec
import Test.QuickCheck

spec :: Spec
spec = describe "fitPage" $ do
  -- C134's prototype: at the default page's width the figures are drawn at
  -- 368 / 3.2 = 115, and a page H tall shrinks them until their captions'
  -- bands fit: (H - 32 - B) / 2 for two rows of unit squares whose bands
  -- total B. That is (368 - 2 x 99.2) / 2 = 84.8 at 400, the captions on
  -- five lines, and (318 - 2 x 149.6) / 2 = 9.4 at 350, a word to a line,
  -- eight; at 500 and
  -- 600 the width's 115 binds first.
  it "shrinks the figures until their captions fit a page of a given height" $
    forM_ [(400, 84.8), (350, 9.4), (500, 115), (600, 115)] $ \(height, expected) -> do
      fitted <- fitOrFail HeightAsGiven defaultPage {pageHeight = height} blintzPage
      fittedPage fitted `shouldBe` defaultPage {pageHeight = height}
      (height, drawnScale fitted) `shouldSatisfy` (\(_, s) -> abs (s - expected) < 1e-9)

  -- Two bands of 149.6 page units, 299.2 together, are taller than the 268
  -- inside a page 300 tall with margins of 16: the bands alone fill it,
  -- whatever the scale.
  it "refuses a page too short for its captions at any scale" $
    fitPage defaultTheme numbered HeightAsGiven defaultPage {pageHeight = 300} blintzPage
      `shouldSatisfy` \case
        Left (TooShortForCaptions 300 16 bands) -> abs (bands - 299.2) < 1e-9
        _ -> False

  -- The bands a page is refused with are those of the round that ran out of
  -- room, a lower bound: a page 150 tall is refused at the width's scale,
  -- its bands 164.8, and one 200 tall, with 168 inside, more than 164.8, is
  -- refused too, at the 299.2 smaller figures wrap to. Red if the refusal's
  -- words claimed the first number is what a page needs.
  it "refuses with the bands of the round that ran out of room, a lower bound" $ do
    let refusedWith height = case fitPage defaultTheme numbered HeightAsGiven defaultPage {pageHeight = height} blintzPage of
          Left (TooShortForCaptions _ _ bands) -> Just bands
          _ -> Nothing
    fmap (\b -> abs (b - 164.8) < 1e-9) (refusedWith 150) `shouldBe` Just True
    fmap (\b -> abs (b - 299.2) < 1e-9) (refusedWith 200) `shouldBe` Just True
    fmap (T.isInfixOf "bands at least 164.8") (either (Just . explain) (const Nothing) (fitPage defaultTheme numbered HeightAsGiven defaultPage {pageHeight = 150} blintzPage))
      `shouldBe` Just True

  -- With no height given, the width sets the scale, 115, and the page is as
  -- tall as the rows need there: two rows of unit squares, each followed by
  -- a band for its four-line captions, 18 + 3 x 16.8 + 14.
  it "makes a page as tall as its rows need when its height is not given" $ do
    fitted <- fitOrFail HeightToFit defaultPage blintzPage
    pageHeight (fittedPage fitted) `shouldSatisfy` (\h -> abs (h - (2 * 16 + 115 * 2 + 2 * 82.4)) < 1e-9)
    drawnScale fitted `shouldSatisfy` (\s -> abs (s - 115) < 1e-9)

  -- A page with no caption is the page as given, laid out as gridOf lays it
  -- out, whichever the height, and is never refused for the room captions
  -- need: so every page drawn before captions is drawn as it was.
  it "leaves a page with no caption as it is" $
    forM_ [HeightAsGiven, HeightToFit] $ \height ->
      forM_ [defaultPage, defaultPage {pageHeight = 40}, defaultPage {pageWidth = 30}] $ \page -> do
        let figures = [(square 1, Nothing), (square 0.5, Just " ")]
        fitPage defaultTheme numbered height page figures
          `shouldBe` Right (FittedPage page <$> gridOf numbered (map fst figures))

  it "has nothing to fit for no figures" $
    fitPage defaultTheme numbered HeightToFit defaultPage [] `shouldBe` Right Nothing

  describe "refuses a page with no room across" $ do
    it "for its own width" $
      fitPage defaultTheme numbered HeightAsGiven defaultPage {pageWidth = 32} blintzPage
        `shouldBe` Left (NoRoomAcross 32 16)
    it "for figures that have no width" $
      fitPage defaultTheme numbered HeightAsGiven defaultPage [(rectangle 0 1, Just "Fold it.")]
        `shouldBe` Left FiguresHaveNoWidth

  -- A sheet seen edge-on, from the front, is a line: its figures have no
  -- height, so they take no room from the captions, and only the width binds.
  it "leaves the width to bind when the figures have no height" $ do
    fitted <- fitOrFail HeightAsGiven defaultPage [edgeOn]
    drawnScale fitted `shouldSatisfy` (\s -> abs (s - 368) < 1e-9)

  -- Such figures need no room, so bands that exactly fill a page leave them
  -- enough: the page a height to fit makes, 64 tall for one one-line band
  -- of 32, is a page of a given height that fits, and one a hair shorter is
  -- not. Red if room had to be more than nothing whatever the figures.
  it "fits figures with no height to a page their bands exactly fill" $ do
    grown <- fitOrFail HeightToFit defaultPage [edgeOn]
    pageHeight (fittedPage grown) `shouldBe` 64
    fitted <- fitOrFail HeightAsGiven defaultPage {pageHeight = 64} [edgeOn]
    drawnScale fitted `shouldSatisfy` (\s -> abs (s - 368) < 1e-9)
    fitPage defaultTheme numbered HeightAsGiven defaultPage {pageHeight = 63.99} [edgeOn]
      `shouldSatisfy` \case
        Left (TooShortForCaptions {}) -> True
        _ -> False

  -- Not a number fails every comparison, so a test of room > 0 refuses it
  -- where a test of room <= 0 would wave it through.
  it "refuses a height that is not a number" $
    fitPage defaultTheme numbered HeightAsGiven defaultPage {pageHeight = 0 / 0} blintzPage
      `shouldSatisfy` \case
        Left (TooShortForCaptions {}) -> True
        _ -> False

  -- The module header's claim, on pages of 1 to 12 figures of three shapes,
  -- with captions of 0 to 14 words, some none, on pages 100 to 800 wide and
  -- 60 to 900 tall. Red if the loop stopped a round early (the page would
  -- not fit), settled at a scale it was not solving for (a larger one
  -- would), or refused a page some scale fits. Stopping a round late cannot
  -- turn it red, and is no fault: at the stop the bands are the ones the
  -- scale was solved for, so another round solves for the same scale.
  --
  -- checkCoverage holds the generator to reaching all three answers, so the
  -- property cannot pass by never meeting one of them. The floors sit well
  -- under what the generator reaches, about 19% of cases height-bound, so
  -- that the check settles quickly on every seed: a floor at the rate itself
  -- leaves it unable to decide, and it fails after 51200 cases.
  it "settles on the largest scale that fits, and refuses only a page none does" $
    checkCoverage $
      forAll genCase $ \(figures, width, height) ->
        let page = defaultPage {pageWidth = width, pageHeight = height}
            inside = height - 32
            widest = (width - 32) / figuresWide figures
            -- Whether a page drawn at s holds its figures and bands, give or
            -- take the slack. The settled scale is allowed rounding; a larger
            -- one is held to the page exactly, since at a scale of 0.1 a
            -- millionth more is less than a slack of a billionth of the page.
            fitsWithin slack s = case captionedRows defaultTheme numbered (scaleOf s) figures of
              Just rows -> s * rowsFigureHeight rows + sum (rowsBands rows) <= inside + slack
              Nothing -> True
            fits = fitsWithin (inside * 1e-9)
            answer = fitPage defaultTheme numbered HeightAsGiven page figures
            settled = case answer of
              Right (Just fitted) -> Just (drawnScale fitted)
              _ -> Nothing
         in cover 5 (isNothing settled) "refused" $
              cover 10 (maybe False (< widest * (1 - 1e-9)) settled) "the height binds" $
                cover 20 (maybe False (>= widest * (1 - 1e-9)) settled) "the width binds" $
                  case answer of
                    Right (Just fitted) ->
                      let s = drawnScale fitted
                       in counterexample ("settled at " <> show s <> ", the width's scale " <> show widest) $
                            counterexample "it does not fit" (fits s)
                              .&&. counterexample "a larger scale fits" (s >= widest * (1 - 1e-9) || not (fitsWithin 0 (s * (1 + 1e-6))))
                              .&&. counterexample "its captions are not wrapped at the scale drawn" (captionsDrawn (fittedDiagram fitted) === concat (wrappedAt s figures))
                    Left (TooShortForCaptions {}) ->
                      let tried = [widest * 2 ** (negate (fromIntegral k) / 8) | k <- [0 .. 400 :: Int]]
                       in counterexample ("fits at " <> show (filter fits tried)) (not (any fits tried))
                    other -> counterexample (show other) False

-- | A sheet seen edge-on, a line with no height, under a one-line caption.
edgeOn :: (Diagram, Maybe Text)
edgeOn = (rectangle 1 0, Just "Fold the left half behind, onto the right.")

-- | The page S24 prototyped on: the blintz's five captions under unit
-- squares, and a sixth figure, half their size, with none.
blintzPage :: [(Diagram, Maybe Text)]
blintzPage =
  [ (square 1, Just "Fold the south-east corner behind, to the centre."),
    (square 1, Just "Fold the north-east corner behind, to the centre."),
    (square 1, Just "Fold the north-west corner behind, to the centre."),
    (square 1, Just "Fold the south-west corner behind, to the centre."),
    (square 1, Just "Reopen the first corner."),
    (square 0.5, Nothing)
  ]

numbered :: Grid
numbered = defaultGrid defaultTheme

ink :: Colour
ink = themeInk defaultTheme

square :: Double -> Diagram
square size = rectangle size size

-- | A rectangle outline, w across and h tall, as its own figure.
rectangle :: Double -> Double -> Diagram
rectangle w h =
  diagramWithExtent
    (Box (V2 0 0) (V2 w h))
    [Polyline (solid ink 1) [V2 0 0, V2 w 0, V2 w h, V2 0 h, V2 0 0]]

scaleOf :: Double -> PageScale
scaleOf s = fromMaybe (error ("not a scale: " <> show s)) (pageScale s)

fitOrFail :: Height -> Page -> [(Diagram, Maybe Text)] -> IO FittedPage
fitOrFail height page figures = case fitPage defaultTheme numbered height page figures of
  Right (Just fitted) -> pure fitted
  other -> fail ("not fitted: " <> show other)

-- | The scale the renderer draws the fitted page at: 'pageTransform''s, not
-- the fit's own, so these tests hold the two to each other.
drawnScale :: FittedPage -> Double
drawnScale fitted = sx
  where
    V2 sx _ = tScale (pageTransform (fittedPage fitted) (fittedDiagram fitted))

-- | How wide the figures are laid out together, at any scale.
figuresWide :: [(Diagram, Maybe Text)] -> Double
figuresWide figures = maybe 0 (\d -> let V2 w _ = boxSize (diagramExtent d) in w) (gridOf numbered (map fst figures))

-- | The text of every caption line on a page, in order.
captionsDrawn :: Diagram -> [Text]
captionsDrawn d = [t | Offset _ (Label _ _ _ t) <- diagramShapes d]

-- | Each figure's caption wrapped at the given scale, as the layout wraps it.
wrappedAt :: Double -> [(Diagram, Maybe Text)] -> [[Text]]
wrappedAt s figures = maybe [] rowsCaptionLines (captionedRows defaultTheme numbered (scaleOf s) figures)

-- | Figures of three shapes with captions of up to 14 words, at least one
-- with a word, on a page of the given width and height.
genCase :: Gen ([(Diagram, Maybe Text)], Double, Double)
genCase = do
  n <- chooseInt (1, 12)
  figures <- vectorOf n ((,) <$> elements [square 1, rectangle 0.5 0.9, rectangle 0.8 0.3] <*> genCaption)
  firstWords <- genWords 1
  let captioned = case figures of
        (d, _) : rest -> (d, Just firstWords) : rest
        [] -> []
  (,,) captioned <$> choose (100, 800) <*> choose (60, 900)
  where
    genCaption = frequency [(1, pure Nothing), (4, Just <$> genWords 0)]
    genWords atLeast = do
      k <- chooseInt (atLeast, 14)
      ws <- vectorOf k (elements ["Fold", "the", "corner", "behind,", "to", "centre.", "extraordinarily", "a"])
      pure (mconcat (zipWith (<>) ("" : repeat " ") ws))
