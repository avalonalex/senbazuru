-- | Six saved vertices reproduce a shallow crossing without a material solve.
module BodyContactDiagnosisSpec (spec) where

import BodyContactDiagnosis
import Data.Either (isLeft)
import FoldContact (ContactRow (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Origami.Contact
import Senbazuru.Origami.Surface
import SurfaceContact qualified as C
import Test.Hspec

spec :: Spec
spec = describe "saved contact diagnosis" $ do
  it "separates crossing extent from a tolerated directional gap" $ do
    cut <- right (pairSection sliver (0, 1))
    sectionCrosses cut `shouldBe` True
    intersectionLength cut `shouldSatisfy` (\x -> abs (x - 9.80185667e-6) < 1e-12)
    check <- right (checkLocalTriangleContact (V3 0 0 1) [(1, 0)] sliver)
    crossingPanels check `shouldBe` [("triangle-0", "triangle-1")]
    reversedOrders check `shouldBe` []
    model <- right (C.prepareTriangleContact 0 (V3 0 0 1) [(1, 0)] sliver)
    ws <- right (C.contactWitnesses model sliver)
    length ws `shouldBe` 4
    let gap = minimum (map (contactGap . C.witnessRow) ws)
    gap `shouldSatisfy` (\x -> x < 0 && x > negate panelTolerance)
    mapM_ (\w -> norm (C.witnessUpper w ^-^ C.witnessLower w ^-^ contactGap (C.witnessRow w) *^ V3 0 0 1) `shouldSatisfy` (< 1e-14)) ws

  it "preserves correction rows and gradients for either height-supplying triangle" $ do
    mapM_
      ( \pair -> do
          model <- right (C.prepareTriangleContact 1e-8 (V3 0 0 1) [pair] sliver)
          ws <- right (C.contactWitnesses model sliver)
          rows <- right (C.orderedContacts model sliver)
          map C.witnessRow ws `shouldBe` rows
          mapM_ (\w -> dot (V3 0 0 1) (C.witnessUpper w ^-^ C.witnessLower w) - C.witnessClearance w - contactGap (C.witnessRow w) `shouldSatisfy` (\x -> abs x < 1e-14)) ws
      )
      [(0, 1), (1, 0)]

  it "does not invent a section for coplanar triangles and rejects invalid ids" $ do
    let flat = sliver {samples = [s {position = let V3 x y _ = position s in V3 x y 0} | s <- samples sliver]}
    cut <- right (pairSection flat (0, 1))
    intersectionEnds cut `shouldBe` []
    sectionCrosses cut `shouldBe` False
    pairSection sliver (0, 9) `shouldSatisfy` isLeft
    pairSection sliver {triangles = [(0, 0, 0), (3, 4, 5)]} (0, 1) `shouldSatisfy` isLeft

-- Triangles 14 and 55 from the project-generated step-2 archive (#322).
-- Distinct material ids are retained; no third-party fixture is used.
sliver :: MaterialMesh
sliver =
  Mesh
    [ Sample (V2 (fromIntegral i) 0) p
      | (i, p) <-
          zip
            [0 :: Int ..]
            [ V3 1.0586546412887619 0.35129620775216713 (-0.0055061952489311936),
              V3 1.1083823808969153 0.45446904455100234 (-0.014377286804006382),
              V3 1.1173089186026437 0.40969928809281636 (-0.011014954842909326),
              V3 1.0671930721219784 0.41168265372644813 (-0.01134016478706129),
              V3 1.1169208967937392 0.41169750857406817 (-0.011164992614878116),
              V3 1.049727904660718 0.49922594565377393 (-0.01788798443726568)
            ]
    ]
    [(0, 1, 2), (3, 4, 5)]

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure
