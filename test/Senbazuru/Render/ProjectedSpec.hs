-- | Small spatial fixtures whose visible areas can be calculated by hand.
module Senbazuru.Render.ProjectedSpec (spec) where

import Data.Either (isLeft)
import Data.Map.Strict qualified as M
import Data.Maybe (isJust)
import Data.Set qualified as S
import Senbazuru.Fold.Query (FoldError (..))
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (signedArea)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Visible
import Senbazuru.Render.Camera
import Senbazuru.Render.Projected
import Test.Hspec
import Test.QuickCheck

spec :: Spec
spec = describe "projected open-fold visibility" $ do
  it "orders sloping faces over their overlap, not by their centres" $ do
    let fr = panels [rectangle 0 10 0 1 const, rectangle 0 1 0 1 (\_ _ -> 2)]
    seen <- visible topDown fr []
    areaOf 0 seen `shouldSatisfy` near 9
    areaOf 1 seen `shouldSatisfy` near 1
  it "gets separated depths from geometry even if a stale order disagrees" $ do
    let fr = panels [rectangle 0 1 0 1 (\_ _ -> 0), rectangle 0 1 0 1 (\_ _ -> 1)]
    seen <- visible topDown fr [FaceOrder (FaceId 0) (FaceId 1) Above]
    map regionFace (formRegions seen) `shouldBe` [FaceId 1]
  it "uses declared order for touching faces and reverses it from underneath" $ do
    let fr = panels [rectangle 0 1 0 1 (\_ _ -> 0), reverse (rectangle 0 1 0 1 (\_ _ -> 0))]
        orders = [FaceOrder (FaceId 0) (FaceId 1) Above]
    above <- visible topDown fr orders
    below <- visible bottomUp fr orders
    map (\r -> (regionFace r, regionTopSide r)) (formRegions above) `shouldBe` [(FaceId 1, False)]
    map (\r -> (regionFace r, regionTopSide r)) (formRegions below) `shouldBe` [(FaceId 0, False)]
  it "declines unresolved touching faces and intersecting panels" $ do
    let flat = rectangle 0 1 0 1 (\_ _ -> 0)
    projectedForm topDown (panels [flat, flat]) [] `shouldBe` Right Nothing
    projectedForm topDown (panels [flat, rectangle 0 1 0 1 (\x _ -> x - 0.5)]) [] `shouldBe` Right Nothing
  it "refuses contradictory pair declarations and invalid indices" $ do
    let flat = rectangle 0 1 0 1 (\_ _ -> 0)
        fr = panels [flat, flat]
    projectedForm topDown fr [FaceOrder (FaceId 0) (FaceId 1) Above, FaceOrder (FaceId 0) (FaceId 1) Below] `shouldSatisfy` isLeft
    projectedForm topDown fr [FaceOrder (FaceId 0) (FaceId 2) Above] `shouldSatisfy` isLeft
  it "declines nonplanar faces and free edge-on paper" $ do
    projectedForm topDown (panels [[[0, 0, 0], [1, 0, 0], [1, 1, 1], [0, 1, 0]]]) [] `shouldBe` Right Nothing
    projectedForm topDown (panels [[[0, 0, 0], [1, 0, 0], [0, 0, 1]]]) [] `shouldBe` Right Nothing
  it "refuses a three-face cycle that would remove a shared patch from every face" $ do
    let flat = rectangle 0 1 0 1 (\_ _ -> 0)
        orders = [FaceOrder (FaceId 0) (FaceId 1) Above, FaceOrder (FaceId 1) (FaceId 2) Above, FaceOrder (FaceId 2) (FaceId 0) Above]
    projectedForm topDown (panels [flat, flat, flat]) orders `shouldBe` Left (ImpossibleStacking (FaceId 0))
  -- The coverage check's first pass skips a cut that would take no more than a
  -- speck of a piece, an area of 1e-9 for a model this size. The second face
  -- covers all of the first but a corner of 2.4 specks, and the third hides
  -- that corner. The last three hide the third, each in front of 0.8 of a
  -- speck of the corner: none of their cuts is made, though between them they
  -- cover all of it. The corner is larger than the patch the next test
  -- refuses, so no rule on a leftover's own size passes both.
  it "accepts a corner hidden by faces that each cover less than a speck of it" $ do
    let e = sqrt 4.8e-9
        -- The corner's long side runs from side 0 to side 1. A line from
        -- (1, 1) to side t cuts off 2t² of the corner for t up to a half, to
        -- within e, so lines to sqrt (1/6) and its mirror cut it in thirds.
        side t = (0.5 - t * e, 0.5 - e + t * e)
        third = sqrt (1 / 6)
        at z = map (\(x, y) -> [x, y, z])
        faces =
          [ at 0 [(0, 0), (0.5, 0), (0.5, 0.5), (0, 0.5)],
            at 0.1 [(0, 0), (0.5, 0), side 0, side 1, (0, 0.5)],
            at 0.2 [side 0, (1, 1), side 1],
            at 0.3 [side 0, (1, 1), side third],
            at 0.3 [side third, (1, 1), side (1 - third)],
            at 0.3 [side (1 - third), (1, 1), side 1]
          ]
    projectedForm topDown (panels faces) [] `shouldSatisfy` either (const False) isJust
  -- Three copies of a 2-speck patch in a cycle each surrender it to another.
  -- Two faces in front, with no order to anything, cover the same 0.6 of a
  -- speck of it. Added up, their covers would leave 0.8 of a speck and pass;
  -- 1.4 specks are in no visible region at all.
  it "refuses a cycle's shared patch that faces in front cover only in part" $ do
    let a = sqrt 4e-9
        q = sqrt 0.6e-9
        at z = map (\(x, y) -> [x, y, z])
        patch = at 0 [(0.5, 0.5), (0.5 + a, 0.5), (0.5, 0.5 + a)]
        faces =
          [ patch,
            patch,
            patch,
            at 0.1 [(0.5, 0), (0.5 + q, 0), (0.5 + q, 0.5 + q), (0.5, 0.5 + q)],
            at 0.2 [(0, 0.5), (0.5 + q, 0.5), (0.5 + q, 0.5 + q), (0, 0.5 + q)]
          ]
        orders = [FaceOrder (FaceId 0) (FaceId 1) Above, FaceOrder (FaceId 1) (FaceId 2) Above, FaceOrder (FaceId 2) (FaceId 0) Above]
    projectedForm topDown (panels faces) orders `shouldBe` Left (ImpossibleStacking (FaceId 0))
  it "clips a buried crease to the exposed ends" $ do
    let fr = panels [rectangle 0 0.5 0 1 (\_ _ -> 0), rectangle 0.5 1 0 1 (\_ _ -> 0), rectangle 0.25 0.75 0.25 0.75 (\_ _ -> 1)]
    seen <- visible topDown fr []
    let centreEdges = [(a, b) | edge <- formEdges seen, let a@(V3 x _ _) = visibleFrom edge, let b@(V3 u _ _) = visibleTo edge, abs (x - 0.5) < 1e-9, abs (u - 0.5) < 1e-9]
    length centreEdges `shouldBe` 2
    sum [abs (v3y b - v3y a) | (a, b) <- centreEdges] `shouldSatisfy` near 0.5
  it "preserves the visible area for arbitrary separated inset panels" $
    forAll (choose (0.1, 0.4)) $ \inset ->
      forAll (choose (0.1, 10)) $ \height ->
        let fr = panels [rectangle 0 1 0 1 (\_ _ -> 0), rectangle inset (1 - inset) inset (1 - inset) (\_ _ -> height)]
         in case projectedForm topDown fr [] of
              Right (Just seen) -> near 1 (areaOf 0 seen + areaOf 1 seen) && near ((1 - 2 * inset) * (1 - 2 * inset)) (areaOf 1 seen)
              _ -> False
  it "works through an oblique viewing basis" $ do
    let fr = panels [rectangle 0 1 0 1 (\_ _ -> 0), rectangle 0 1 0 1 (\_ _ -> 1)]
    projectedForm isometric fr [] `shouldSatisfy` either (const False) isJust
  -- A face of the unit square, under a copy of itself moved towards the viewer
  -- with one corner cut off, shows only that corner. Seen isometrically the
  -- square's shadow is sqrt 2 across, so the visible regions are cut with a
  -- speck of 2e-9. The model's own spans, 1.1 in 3D, give 1.21e-9. A corner
  -- between the two used to be dropped by the cutting and then found
  -- uncovered by the coverage check, and refused as a cycle.
  it "judges what a shadow leaves uncovered by the speck its regions were cut with" $
    forAll (choose (0.5e-9, 3e-9)) $ \corner ->
      let towards = map (zipWith (+) [0.1, -0.1, 0.1])
       in projectedForm isometric (cornerShown corner (sqrt 3) towards) [] `shouldSatisfy` either (const False) isJust
  -- Turning the camera about its line of sight changes nothing in the picture
  -- but its axes, and so the shadow's axis-aligned spans: rolled by 45° the
  -- unit square's are sqrt 2, not 1. Whether a view can be drawn must not
  -- depend on that.
  it "draws a view however the camera is rolled" $
    forAll (choose (0, 2 * pi)) $ \roll ->
      forAll (choose (0.5e-9, 3e-9)) $ \corner ->
        let towards = map (zipWith (+) [0, 0, 0.1])
         in projectedForm (turnedBy roll topDown) (cornerShown corner 1 towards) [] `shouldSatisfy` either (const False) isJust
  -- A square with a smaller square at its centre and four trapezoids round it.
  -- Seen isometrically the centre's shadow is 1.5e-9, between this frame's two
  -- specks, 1e-9 from its 3D spans and 2e-9 from its picture: too small to
  -- paint, but it was kept as a face and then refused as the file's fault, a
  -- face without a normal. It is dropped like any other face too small to
  -- paint, and its edges all belong to the trapezoids.
  it "drops a face too small to paint rather than calling the file faulty" $ do
    let side = sqrt (sqrt 3 * 1.5e-9)
    seen <- visible isometric (centredSquare side []) []
    S.fromList (map regionFace (formRegions seen)) `shouldBe` S.fromList (map FaceId [0 .. 3])
  -- The other way round: a copy of the outer square 10 below makes the model
  -- deeper along the line of sight than the picture is wide, so its 3D speck,
  -- 1e-7, is the larger. A centre of 5e-9 was dropped by that speck, and the
  -- paper 10 below showed through the hole it left. It is painted.
  it "paints a face the picture can show however deep the model is" $ do
    let below = [[0, 0, -10], [1, 0, -10], [1, 1, -10], [0, 1, -10]]
    seen <- visible topDown (centredSquare (sqrt 5e-9) below) []
    S.fromList (map regionFace (formRegions seen)) `shouldBe` S.fromList (map FaceId [0 .. 4])

-- | The unit square at z = 0, under a copy of itself moved by @towards@ with
-- its (1, 1) corner cut off, so that only that corner of the first face shows.
-- The corner's shadow is @corner@ when the view divides areas in the xy plane
-- by @foreshortening@: the corner's legs are then
-- sqrt (2 * foreshortening * corner).
cornerShown :: Double -> Double -> ([[Double]] -> [[Double]]) -> Frame
cornerShown corner foreshortening towards = panels [square, towards cut]
  where
    leg = sqrt (2 * foreshortening * corner)
    square = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]]
    cut = [[0, 0, 0], [1, 0, 0], [1, 1 - leg, 0], [1 - leg, 1, 0], [0, 1, 0]]

rectangle :: Double -> Double -> Double -> Double -> (Double -> Double -> Double) -> [[Double]]
rectangle x0 x1 y0 y1 z = [[x, y, z x y] | (x, y) <- [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]]

panels :: [[[Double]]] -> Frame
panels rings =
  emptyFrame
    { frameClasses = ["foldedForm"],
      verticesCoords = concat rings,
      facesVertices = ids,
      edgesVertices = concat [zip vs (drop 1 vs ++ take 1 vs) | vs <- ids],
      edgesAssignment = replicate (sum (map length rings)) Border
    }
  where
    ids = [map VertexId [offset .. offset + length ring - 1] | (offset, ring) <- zip (scanl (+) 0 (map length rings)) rings]

-- | The unit square at z = 0 as four trapezoids round a centred square of side
-- @side@, faces 0 to 3 and 4, and then @extra@ as one more face, 5, if given.
centredSquare :: Double -> [[Double]] -> Frame
centredSquare side extra = mesh (corners ++ extra) (rings ++ [[8 .. 7 + length extra] | not (null extra)])
  where
    (lo, hi) = (0.5 - side / 2, 0.5 + side / 2)
    corners = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0], [lo, lo, 0], [hi, lo, 0], [hi, hi, 0], [lo, hi, 0]]
    rings = [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7]]

-- | Faces sharing their vertices, as a folded pattern's do. The outline is the
-- sheet's border; every edge two faces share is an unfolded crease.
mesh :: [[Double]] -> [[Int]] -> Frame
mesh coords rings =
  emptyFrame
    { frameClasses = ["foldedForm"],
      verticesCoords = coords,
      facesVertices = map (map VertexId) rings,
      edgesVertices = [(VertexId a, VertexId b) | (a, b) <- M.keys uses],
      edgesAssignment = [if n == 1 then Border else Flat | n <- M.elems uses]
    }
  where
    uses = M.fromListWith (+) [((min a b, max a b), 1 :: Int) | vs <- rings, (a, b) <- zip vs (drop 1 vs ++ take 1 vs)]

visible :: Basis -> Frame -> [FaceOrder] -> IO VisibleForm
visible basis fr orders = case projectedForm basis fr orders of
  Right (Just seen) -> pure seen
  result -> expectationFailure (show result) >> fail "expected visible paper"

areaOf :: Int -> VisibleForm -> Double
areaOf i seen = sum [abs (signedArea [V2 x y | V3 x y _ <- piece]) | r <- formRegions seen, regionFace r == FaceId i, piece <- regionPieces r]

near :: Double -> Double -> Bool
near expected actual = abs (expected - actual) < 1e-8
