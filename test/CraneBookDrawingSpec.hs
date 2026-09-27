-- | Presentation may remove ink, never a flap boundary or visible paper.
module CraneBookDrawingSpec (spec) where

import CraneBookDrawing
import Senbazuru.Diagram (Shape (..))
import Senbazuru.Fold.Types (FaceId (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (signedArea)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Surface (Mesh (..), Sample (..))
import Senbazuru.Origami.Visible
import Senbazuru.Render.Camera (topDown)
import Test.Hspec

spec :: Spec
spec = describe "instruction-book crane presentation" $ do
  it "keeps a curved source panel in one tone across its subdivision" $ do
    let ps = [V3 0 0 0, V3 1 0 0, V3 1 1 0, V3 0 1 1]
        mesh = Mesh (zipWith Sample square ps) [(0, 1, 2), (0, 2, 3)]
        seen = VisibleForm [Region (FaceId 0) True [[V3 0 0 0, V3 1 0 0, V3 1 1 0]], Region (FaceId 1) True [[V3 0 0 0, V3 1 1 0, V3 0 1 1]]] [] []
    drawing <- either (fail . show) pure (bookDrawing topDown [FaceId 0, FaceId 0] mesh seen)
    length [() | (_, rings) <- bookTones drawing, not (null rings)] `shouldBe` 1
    sum (map (area . snd) (bookTones drawing)) `shouldSatisfy` near 1
  it "removes triangulation edges without erasing the outer boundary" $ do
    let segments = contourSegments [([V2 0 0, V2 1 0, V2 1 1], const 0), ([V2 0 0, V2 1 1, V2 0 1], const 0)]
    length segments `shouldBe` 4
    sum (map lineLength segments) `shouldSatisfy` near 4
  it "cancels one long boundary against several clipped neighbours" $ do
    let segments = contourSegments [(square, const 0), ([V2 1 0, V2 2 0, V2 2 0.5, V2 1 0.5], const 0), ([V2 1 0.5, V2 2 0.5, V2 2 1, V2 1 1], const 0)]
    sum (map lineLength segments) `shouldSatisfy` near 6
    segments `shouldSatisfy` all (\(V2 a _, V2 b _) -> a /= 1 || b /= 1)
  it "retains a visible overlap edge between different-depth layers" $ do
    let segments = contourSegments [(square, const 0), ([V2 1 0, V2 2 0, V2 2 1, V2 1 1], const 0.2)]
    sum (map lineLength segments) `shouldSatisfy` near 8
  it "removes a crease join only when depth agrees along the whole edge" $ do
    let rightHalf = [V2 1 0, V2 2 0, V2 2 1, V2 1 1]
        continuous = contourSegments [(square, const 0), (rightHalf, \(V2 x _) -> x - 1)]
        midpointOnly = contourSegments [(square, const 0), (rightHalf, \(V2 _ y) -> y - 0.5)]
    sum (map lineLength continuous) `shouldSatisfy` near 6
    sum (map lineLength midpointOnly) `shouldSatisfy` near 8
  it "omits short crease ink but keeps even shorter contours" $ do
    let short = (V2 0 0, V2 0.001 0)
        long = (V2 0 0, V2 0.1 0)
        drawing = BookDrawing [] [short] [short, long]
    selectedCreases 2 [short, long] `shouldBe` ([long], [short])
    [points | Polyline _ points <- bookShapes 2 drawing] `shouldBe` [[fst long, snd long], [fst short, snd short]]
  it "renders either paper side with the same coverage and light-facing tone" $ do
    let ps = [V3 0 0 0, V3 1 0 0, V3 0 1 0]
        mesh = Mesh (zipWith Sample [V2 0 0, V2 1 0, V2 0 1] ps) [(0, 1, 2)]
        seen = VisibleForm [Region (FaceId 0) True [ps]] [] []
    a <- either (fail . show) pure (bookDrawing topDown [FaceId 0] mesh seen)
    b <- either (fail . show) pure (bookDrawing topDown [FaceId 0] mesh {triangles = [(0, 2, 1)]} seen {formRegions = [Region (FaceId 0) False [ps]]})
    map (area . snd) (bookTones a) `shouldBe` map (area . snd) (bookTones b)
    sum (map (area . snd) (bookTones a)) `shouldSatisfy` near 0.5
  where
    square = [V2 0 0, V2 1 0, V2 1 1, V2 0 1]
    area = sum . map (abs . signedArea)
    lineLength (a, b) = norm (b ^-^ a)
    near expected actual = abs (actual - expected) < 1e-10
