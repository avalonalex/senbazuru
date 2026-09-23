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

  it "can cross the plane threshold while the overlap gap and intersection improve" $ do
    retained <- right (pairSection finalRetained (0, 1))
    refused <- right (pairSection finalRefused (0, 1))
    sectionCrosses retained `shouldBe` False
    sectionCrosses refused `shouldBe` True
    -- Independently calculated from the saved decimal coordinates at 60-digit
    -- precision. Vertex 27 is the last vertex of triangle 46 in this fixture.
    mapM_
      ( \(cut, expected) -> case firstDistances cut of
          [_, _, distance] -> abs (distance - expected) `shouldSatisfy` (< 1e-17)
          _ -> expectationFailure "expected three signed vertex distances"
      )
      [(retained, -9.999945711955125e-8), (refused, -1.0000007754248323e-7)]
    intersectionLength retained `shouldSatisfy` (> panelTolerance)
    intersectionLength refused `shouldSatisfy` (< intersectionLength retained)
    mapM_
      ( \(mesh, crossings) -> do
          check <- right (checkLocalTriangleContact (V3 0 0 1) [(0, 1)] mesh)
          crossingPanels check `shouldBe` crossings
          reversedOrders check `shouldBe` []
      )
      [(finalRetained, []), (finalRefused, [("triangle-0", "triangle-1")])]
    let minimumGap mesh = do
          model <- right (C.prepareTriangleContact 0 (V3 0 0 1) [(0, 1)] mesh)
          ws <- right (C.contactWitnesses model mesh)
          length ws `shouldBe` 4
          pure (minimum (map (contactGap . C.witnessRow) ws))
    retainedGap <- minimumGap finalRetained
    refusedGap <- minimumGap finalRefused
    retainedGap `shouldSatisfy` (\x -> x < 0 && x > negate panelTolerance)
    refusedGap `shouldSatisfy` (> retainedGap)

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

-- Project-generated attempt ten from #340, triangles 46 and 70. The order is
-- original vertices [50,86,27,81,71,20]. These are two numerical trials of one
-- saved proposal, not new solves or an interpolated folding instruction.
finalRetained, finalRefused :: MaterialMesh
finalRetained =
  sixVertices
    [ V3 1.051782146366629 0.37455104825549895 (-0.008880071587116128),
      V3 1.0517882101837042 0.2498690881293495 3.0327397489215543e-05,
      V3 1.1035643366361547 0.24988957381194024 0.0002816951191667549,
      V3 1.067152433360474 0.162270486925271 (-0.005956797437990051),
      V3 1.1169083282006596 0.4116295667765462 0.01185639764139633,
      V3 1.1343606776724133 0.3240651567518924 0.0055628546094040505
    ]
finalRefused =
  sixVertices
    [ V3 1.0517821464191983 0.3745510486421728 (-0.008880066656275429),
      V3 1.0517882103224527 0.24986908834624785 3.032997318308818e-05,
      V3 1.1035643367449237 0.24988957450722535 0.0002817039133343278,
      V3 1.0671524332109668 0.16227048592199605 (-0.005956783717936824),
      V3 1.1169083281492092 0.4116295665219719 0.01185640054541962,
      V3 1.1343606775900708 0.32406515638054584 0.005562859055178792
    ]

sixVertices :: [V3] -> MaterialMesh
sixVertices ps = Mesh [Sample (V2 (fromIntegral i) 0) p | (i, p) <- zip [0 :: Int ..] ps] [(0, 1, 2), (3, 4, 5)]
