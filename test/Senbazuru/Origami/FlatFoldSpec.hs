-- |
-- Tests for the flat-foldability checks.
--
-- Two styles, because the two theorems have different shapes. Maekawa's is
-- about counting, so it is tested by example: a handful of vertices whose
-- verdict a person can work out on paper. Kawasaki's is about angles, so it is
-- tested by property: 'genKawasakiSectors' builds vertices that satisfy it /by
-- construction/ — pick the odd-numbered sector angles to sum to 180°, and the
-- even-numbered ones too — and the properties say that such a vertex passes and
-- that nudging one crease makes it fail.
--
-- Every generated vertex is given @U@ creases and a border ring, which isolates
-- what is under test: @U@ stops Maekawa being applied at all, so a Kawasaki
-- failure cannot be confused with a counting failure, and the ring makes the
-- outer vertices border vertices, so they are skipped rather than each
-- reporting a single dangling crease.
module Senbazuru.Origami.FlatFoldSpec (spec) where

import Data.ByteString qualified as BS
import Senbazuru.Fold.Load (decodeFoldFile)
import Senbazuru.Fold.Types
  ( Assignment (..),
    EdgeId (..),
    Frame (..),
    VertexId (..),
    emptyFrame,
    keyFrame,
  )
import Senbazuru.Origami.FlatFold
import Test.Hspec
import Test.QuickCheck

-- | A frame with one interior vertex at the origin, one crease along each given
-- bearing, and a border ring joining their far ends.
--
-- The ring is what makes the outer vertices border vertices. Without it each
-- would be an interior vertex of degree one and would report Maekawa's
-- corollary, drowning the vertex actually under test.
starFrame :: [(Double, Assignment)] -> Frame
starFrame spokes =
  emptyFrame
    { verticesCoords = [0, 0] : [[cos b, sin b] | (b, _) <- spokes],
      edgesVertices = creases <> ring,
      edgesAssignment = map snd spokes <> replicate n Border
    }
  where
    n = length spokes
    creases = [(VertexId 0, VertexId i) | i <- [1 .. n]]
    ring = [(VertexId i, VertexId (wrap (i + 1))) | i <- [1 .. n]]
    wrap i = if i > n then 1 else i

-- | The same, with every crease at a right angle to the last.
squareStar :: [Assignment] -> Frame
squareStar as = starFrame (zip [0, pi / 2, pi, 3 * pi / 2] as)

-- | A star whose creases are all unassigned, which leaves Kawasaki's theorem as
-- the only check that can fire.
unassignedStar :: [Double] -> Frame
unassignedStar bearings = starFrame [(b, Unassigned) | b <- bearings]

-- | Bearings running counterclockwise from zero, given the sectors between
-- them.
bearingsOf :: [Double] -> [Double]
bearingsOf = init . scanl (+) 0

-- | The verdict for the vertex at the origin, which every frame here has at
-- id 0.
centreOf :: Frame -> Either CheckError (Maybe VertexCheck)
centreOf fr = do
  report <- checkFrame defaultTolerance fr
  pure $ case [c | c <- reportChecked report, checkVertex c == VertexId 0] of
    (c : _) -> Just c
    [] -> Nothing

violationsAt :: Frame -> Either CheckError [Violation]
violationsAt fr = fmap (maybe [] checkViolations) (centreOf fr)

-- | Sector angles for a vertex that satisfies Kawasaki's theorem exactly.
--
-- Built rather than searched for: alternate sectors have to sum to 180° each,
-- so generate two lists and scale each to π. The lower bound of 0.2 before
-- scaling keeps every sector comfortably wide, which matters for the nudge
-- property below: a nudge must not be large enough to reorder the
-- creases around the vertex.
genKawasakiSectors :: Gen [Double]
genKawasakiSectors = do
  n <- choose (2, 5)
  odds <- vectorOf n (choose (0.2, 1.0))
  evens <- vectorOf n (choose (0.2, 1.0))
  pure (interleave (toHalfTurn odds) (toHalfTurn evens))
  where
    toHalfTurn xs = map (* (pi / sum xs)) xs
    interleave (x : xs) (y : ys) = x : y : interleave xs ys
    interleave xs [] = xs
    interleave [] ys = ys

spec :: Spec
spec = do
  describe "Maekawa's theorem" $ do
    it "rejects an odd number of creases, whatever they are assigned" $ do
      -- The corollary is the cheapest check in the whole project: it reads no
      -- coordinates and does not care which crease is which.
      let threeCreases as = violationsAt (starFrame (zip [0, 2, 4] as))
      threeCreases [Mountain, Valley, Mountain] `shouldBe` Right [OddCreaseCount 3]
      threeCreases [Mountain, Mountain, Mountain] `shouldBe` Right [OddCreaseCount 3]
      threeCreases [Unassigned, Unassigned, Unassigned] `shouldBe` Right [OddCreaseCount 3]

    it "accepts three mountains and one valley at right angles" $
      -- A square folded into quarters. Fold it in half, then in half again: the
      -- second fold goes through two layers, which unfold into two creases
      -- folded opposite ways. That is where the lopsided 3-to-1 comes from.
      violationsAt (squareStar [Mountain, Valley, Mountain, Mountain])
        `shouldBe` Right []

    it "rejects two mountains and two valleys at right angles" $
      -- The obvious-looking assignment, and impossible: a vertical valley
      -- crossing a horizontal mountain cannot be pressed flat.
      violationsAt (squareStar [Mountain, Valley, Mountain, Valley])
        `shouldBe` Right [MaekawaImbalance 2 2]

    it "is not applied when any crease is unassigned" $ do
      -- U means "not decided yet", so the counts are unknown and Maekawa has
      -- nothing to say. Reporting a violation here would be a checker
      -- complaining about a file that has not made its mind up.
      let fr = squareStar [Mountain, Mountain, Valley, Unassigned]
      violationsAt fr `shouldBe` Right []
      fmap (fmap checkUnassigned) (centreOf fr) `shouldBe` Right (Just 1)

  describe "Kawasaki's theorem" $ do
    it "rejects sectors that do not alternate to zero" $ do
      -- Sectors of 90, 90, 135 and 45 degrees: 90 - 90 + 135 - 45 = 90.
      let fr = unassignedStar (bearingsOf [pi / 2, pi / 2, 3 * pi / 4, pi / 4])
      violationsAt fr `shouldSatisfy` \case
        Right [KawasakiSum s] -> abs (abs s - 90) < 1e-9
        _ -> False

    it "holds for any vertex whose alternate sectors each sum to 180 degrees" $
      forAll genKawasakiSectors $ \sectors ->
        let fr = unassignedStar (bearingsOf sectors)
         in violationsAt fr == Right []

    it "fails once one crease is nudged off that arrangement" $
      -- Moving a single crease by d changes the two sectors either side of it
      -- by +d and -d. Those sit at opposite signs in the alternating sum, so
      -- the sum moves by 2d rather than cancelling.
      forAll ((,) <$> genKawasakiSectors <*> choose (0.001, 0.05)) $ \(sectors, nudge) ->
        let bearings = bearingsOf sectors
            moved = case bearings of
              (b0 : b1 : rest) -> b0 : (b1 + nudge) : rest
              short -> short
            fr = unassignedStar moved
         in violationsAt fr /= Right []

    it "does not depend on which crease the walk starts at" $
      -- The alternating sum flips sign if you start one crease further round,
      -- so only its distance from zero can mean anything. Rotating the whole
      -- vertex must not change the verdict.
      forAll genKawasakiSectors $ \sectors ->
        let rotated = drop 1 sectors <> take 1 sectors
            check ss = violationsAt (unassignedStar (bearingsOf ss))
         in check sectors == check rotated

  describe "which lines count as creases" $ do
    it "dissolves a flat crease instead of counting it" $ do
      -- Four folds at right angles plus an F line at 45 degrees. Counted, that
      -- is five creases -- odd, and Maekawa's corollary would fire. Dissolved,
      -- it is the four folds again and the vertex is fine.
      let fr =
            starFrame
              [ (0, Mountain),
                (pi / 4, Flat),
                (pi / 2, Mountain),
                (pi, Mountain),
                (3 * pi / 2, Valley)
              ]
      violationsAt fr `shouldBe` Right []
      fmap (fmap checkDegree) (centreOf fr) `shouldBe` Right (Just 4)

    it "dissolves a join the same way" $ do
      let fr =
            starFrame
              [ (0, Mountain),
                (pi / 4, Join),
                (pi / 2, Mountain),
                (pi, Mountain),
                (3 * pi / 2, Valley)
              ]
      violationsAt fr `shouldBe` Right []

    it "skips a vertex the edge of the paper reaches" $ do
      -- Three creases and a border edge. Left to itself this vertex would
      -- report Maekawa's corollary; on the border the theorem does not apply,
      -- because the sectors do not go all the way round.
      let fr = starFrame (zip [0, 1, 2, 3] [Mountain, Valley, Mountain, Border])
      centreOf fr `shouldBe` Right Nothing
      fmap (lookup (VertexId 0) . reportSkipped) (checkFrame defaultTolerance fr)
        `shouldBe` Right (Just OnBorder)

    it "skips a vertex a cut reaches" $ do
      let fr = starFrame (zip [0, 1, 2, 3] [Mountain, Valley, Mountain, Cut])
      fmap (lookup (VertexId 0) . reportSkipped) (checkFrame defaultTolerance fr)
        `shouldBe` Right (Just OnBorder)

  describe "the star of creases around a vertex" $ do
    it "measures sectors that sum to a full turn" $
      forAll genKawasakiSectors $ \sectors ->
        let fr = unassignedStar (bearingsOf sectors)
            centre = fmap (take 1) (frameStars fr)
         in case centre of
              Right [st] -> abs (sum (starSectors st) - 2 * pi) < 1e-9
              _ -> False

    it "gives a lone crease the whole turn as its one sector" $ do
      -- The wrap-around case that the general formula gets wrong: comparing the
      -- single bearing with itself gives 0, not 2*pi. Built by hand rather than
      -- with starFrame, whose border ring would close a one-crease vertex into
      -- an edge from a vertex to itself.
      let fr =
            emptyFrame
              { verticesCoords = [[0, 0], [1, 0]],
                edgesVertices = [(VertexId 0, VertexId 1)],
                edgesAssignment = [Mountain]
              }
      fmap (map starSectors . take 1) (frameStars fr) `shouldBe` Right [[2 * pi]]

  describe "frames the question does not apply to" $ do
    it "refuses a folded form, which is not a crease pattern" $ do
      let fr =
            emptyFrame
              { verticesCoords = [[0, 0, 0], [1, 0, 0], [0, 1, 0.5]],
                edgesVertices = [(VertexId 0, VertexId 1), (VertexId 0, VertexId 2)],
                edgesAssignment = [Mountain, Valley]
              }
      checkFrame defaultTolerance fr
        `shouldBe` Left (NotACreasePattern (VertexId 2) 0.5)

    it "refuses an edge with no direction" $ do
      -- Two vertices at the same point: the edge between them has no bearing,
      -- so it has no place in the rotational order at either end.
      let fr =
            emptyFrame
              { verticesCoords = [[0, 0], [0, 0]],
                edgesVertices = [(VertexId 0, VertexId 1)],
                edgesAssignment = [Mountain]
              }
      checkFrame defaultTolerance fr `shouldBe` Left (DegenerateEdge (EdgeId 0))

  describe "the example files" $ do
    it "passes the square folded into quarters" $ do
      report <- checkFixture "test/fixtures/quarter-fold.fold"
      reportViolations report `shouldBe` []
      length (reportChecked report) `shouldBe` 1

    it "fails the three-crease vertex" $ do
      report <- checkFixture "test/fixtures/three-crease.fold"
      map snd (reportViolations report) `shouldBe` [OddCreaseCount 3]

    it "passes a vertex the Big-Little-Big lemma rules out" $ do
      -- A known limitation, pinned here so that implementing the lemma has to
      -- come to this test and change it on purpose. The sectors are 90, 30, 90
      -- and 150 degrees: Kawasaki's alternating sum is zero and Maekawa counts
      -- three mountains to one valley, but the 30 degree sector is strictly
      -- smaller than both its neighbours, so the two creases bounding it have
      -- to differ, and both are mountains.
      -- See docs/notes/big-little-big.md.
      report <- checkFixture "test/fixtures/big-little-big.fold"
      reportViolations report `shouldBe` []

    it "finds no interior vertex in the unit square, whose creases cross unrecorded" $ do
      -- Every vertex of unit-square.fold sits on the border: its three interior
      -- creases cross at the centre without a vertex there, so there is nothing
      -- for either theorem to look at.
      report <- checkFixture "test/fixtures/unit-square.fold"
      reportChecked report `shouldBe` []

checkFixture :: FilePath -> IO Report
checkFixture path = do
  bytes <- BS.readFile path
  case decodeFoldFile bytes of
    Left err -> fail ("decode failed: " <> err)
    Right f -> case checkFrame defaultTolerance (keyFrame f) of
      Left err -> fail ("check failed: " <> show err)
      Right report -> pure report
