-- | Check contact independently of the folding engine and the viewer. These
-- small polygons distinguish touching, crossing and reversed panel order.
module PanelContactSpec (spec) where

import Control.Monad (forM_)
import Data.Either (isLeft)
import Data.Text (Text)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Contact
import Test.Hspec
import Test.QuickCheck

spec :: Spec
spec = describe "rigid study panel contact" $ do
  it "detects an upright panel crossing a horizontal panel" $ do
    result <- report [] [base, vertical 0 (-0.5) 0.5 (-1) 1]
    crossingPanels result `shouldBe` [("base", "flap")]
    contactPassed result `shouldBe` False
  it "rejects plane intersections outside the actual polygons" $ do
    result <- report [] [base, vertical 0 2 3 (-1) 1]
    crossingPanels result `shouldBe` []
    contactPassed result `shouldBe` True
  it "does not extend a plane section to a nearby off-plane corner" $ do
    -- The planes meet at x=0. The lower cut ends at y=10/21, whereas
    -- the upper cut begins at 39/80: their separation is 19/1680.
    -- The lower tip is only 1.25e-8 from the upper plane, but including
    -- its y=1/2 would invent an overlap. Moving the upper base to 15/32
    -- makes a real crossing and must still fail at the same tolerance.
    forM_ [39 / 80, 15 / 32] $ \baseY ->
      forM_ [id, reverse] $ \winding ->
        forM_ [id, \(V3 x y z) -> V3 (z + 0.1) (x - 0.2) (y + 0.3)] $ \transform -> do
          let lower = Panel "lower" [V3 (-0.25) 0 0, V3 0.25 0 0, V3 0.0125 0.5 0]
              upper = Panel "upper" [V3 (-0.25) baseY (-2.5e-7), V3 0.25 baseY 2.5e-7, V3 0 0.75 0]
              -- Subtract the transformed origin: directions do not translate.
              axis = case (transform up, transform (V3 0 0 0)) of
                (V3 x y z, V3 a b c) -> V3 (x - a) (y - b) (z - c)
          checked <- either (fail . show) pure (checkPanelContact axis [("lower", "upper")] [p {panelCorners = map transform (winding (panelCorners p))} | p <- [lower, upper]])
          crossingPanels checked `shouldBe` [("lower", "upper") | baseY < 10 / 21]
          contactPassed checked `shouldBe` (baseY > 10 / 21)
  it "allows a shared hinge and checks the height of its upright flap" $ do
    result <- report [("base", "flap")] [base, vertical 1 (-1) 1 0 1]
    checkedPanelPairs result `shouldBe` 1
    contactPassed result `shouldBe` True
    below <- report [("base", "flap")] [base, vertical 1 (-1) 1 (-1) 0]
    crossingPanels below `shouldBe` []
    reversedOrders below `shouldBe` [("base", "flap", 1)]
  it "detects reversed separated layers even when they do not cross" $ do
    result <- report [("base", "flap")] [base, horizontal "flap" (-0.1)]
    crossingPanels result `shouldBe` []
    reversedOrders result `shouldBe` [("base", "flap", 0.1)]
  it "does not impose order where the two projected outlines do not meet" $ do
    let away = (horizontal "flap" (-1)) {panelCorners = [V3 (x + 4) y z | V3 x y z <- panelCorners (horizontal "flap" (-1))]}
    result <- report [("base", "flap")] [base, away]
    contactPassed result `shouldBe` True
  it "checks overlapping shadows even when neither contains the other's vertices" $ do
    let lower = Panel "base" [V3 (-2) (-1) 0, V3 2 (-1) 0, V3 0 2 0]
        upper = Panel "flap" [V3 (-2) 1 (-0.1), V3 0 (-2) (-0.1), V3 2 1 (-0.1)]
    result <- report [("base", "flap")] [lower, upper]
    reversedOrders result `shouldBe` [("base", "flap", 0.1)]
  it "allows numerical contact noise within the distance tolerance" $ do
    result <- report [("base", "flap")] [base, horizontal "flap" (-(0.5 * panelTolerance))]
    contactPassed result `shouldBe` True
    outside <- report [("base", "flap")] [base, horizontal "flap" (-(2 * panelTolerance))]
    reversedOrders outside `shouldSatisfy` (not . null)
  it "checks order when the lower panel is vertical" $ do
    result <- report [("flap", "base")] [base, vertical 1 (-1) 1 0 1]
    reversedOrders result `shouldBe` [("flap", "base", 1)]
  it "requires an order for overlapping coplanar interiors" $ do
    unranked <- report [] [base, horizontal "flap" 0]
    unorderedContacts unranked `shouldBe` [("base", "flap")]
    ordered <- report [("base", "flap")] [base, horizontal "flap" 0]
    contactPassed ordered `shouldBe` True
  it "permits coplanar edge contact without inventing an order" $ do
    let next = Panel "flap" [V3 1 (-1) 0, V3 2 (-1) 0, V3 2 1 0, V3 1 1 0]
    result <- report [] [base, next]
    contactPassed result `shouldBe` True
  it "uses the distance tolerance for narrow coplanar seam overlaps" $ do
    forM_ [0.5, 2] $ \multiple -> do
      let width = multiple * panelTolerance
          next = Panel "flap" [V3 (1 - width) (-1) 0, V3 2 (-1) 0, V3 2 1 0, V3 (1 - width) 1 0]
          rotate (V3 x y z) = V3 z x y
      forM_ [id, rotate] $ \transform ->
        forM_ [id, reverse] $ \winding -> do
          result <- either (fail . show) pure (checkPanelContact (transform up) [] [p {panelCorners = map transform (winding (panelCorners p))} | p <- [base, next]])
          contactPassed result `shouldBe` (multiple < 1)
          unorderedContacts result `shouldBe` [("base", "flap") | multiple >= 1]
  it "uses transitive orders for coplanar stacks" $ do
    result <- report [("base", "middle"), ("middle", "top")] [base, horizontal "middle" 0, horizontal "top" 0]
    checkedPanelPairs result `shouldBe` 3
    contactPassed result `shouldBe` True
  it "keeps branches unordered while following longer layer-order chains" $ do
    let panels = [horizontal name 0 | name <- ["base", "middle", "top", "branch", "end"]]
        links = [("base", "middle"), ("middle", "top"), ("middle", "branch"), ("top", "end"), ("branch", "end")]
    result <- report links panels
    unorderedContacts result `shouldBe` [("top", "branch")]
    complete <- report (("top", "branch") : links) panels
    contactPassed complete `shouldBe` True
    checkPanelContact up (("end", "base") : links) panels `shouldSatisfy` isLeft
  it "reports an order parallel to both panels as unchecked" $ do
    result <- report [("base", "flap")] [(vertical 0 0 1 0 1) {panelName = "base"}, vertical 1 0 1 0 1]
    uncheckedOrders result `shouldBe` [("base", "flap")]
    contactPassed result `shouldBe` False
  it "rejects invalid directions, names, cycles and degenerate panels" $ do
    checkPanelContact (V3 0 0 0) [] [base] `shouldSatisfy` isLeft
    checkPanelContact (V3 (0 / 0) 0 1) [] [base] `shouldSatisfy` isLeft
    checkPanelContact up [("base", "missing")] [base] `shouldSatisfy` isLeft
    checkPanelContact up [("base", "base")] [base] `shouldSatisfy` isLeft
    checkPanelContact up [("base", "flap"), ("flap", "base")] [base, horizontal "flap" 1] `shouldSatisfy` isLeft
    checkPanelContact up [] [base, base] `shouldSatisfy` isLeft
    checkPanelContact up [] [Panel "empty" []] `shouldSatisfy` isLeft
    checkPanelContact up [] [Panel "line" [V3 0 0 0, V3 1 0 0, V3 2 0 0]] `shouldSatisfy` isLeft
    checkPanelContact up [] [Panel "bent" [V3 0 0 0, V3 1 0 0, V3 1 1 0, V3 0 1 0.1]] `shouldSatisfy` isLeft
    checkPanelContact up [] [Panel "concave" [V3 0 0 0, V3 1 0 0, V3 0.5 0.5 0, V3 1 1 0, V3 0 1 0]] `shouldSatisfy` isLeft
  it "ignores face winding" $ do
    let panels = [base, vertical 0 (-0.5) 0.5 (-1) 1]
        reversed = [p {panelCorners = reverse (panelCorners p)} | p <- panels]
    checkPanelContact up [] reversed `shouldBe` checkPanelContact up [] panels
  it "is invariant under rigid rotation when the order direction rotates too" $
    forAll (choose (-pi, pi)) $ \angle ->
      let rotate (V3 x y z) = V3 (cos angle * x + sin angle * z) y (-(sin angle * x) + cos angle * z)
          panels = [base, horizontal "flap" (-0.1), (vertical 0 (-0.5) 0.5 (-1) 1) {panelName = "crossing"}]
          result = checkPanelContact (rotate up) [("base", "flap")] [p {panelCorners = map rotate (panelCorners p)} | p <- panels]
       in case result of
            Left err -> counterexample (show err) False
            Right checked ->
              property $
                crossingPanels checked == [("base", "crossing"), ("flap", "crossing")]
                  && case reversedOrders checked of
                    [("base", "flap", gap)] -> abs (gap - 0.1) < 1e-12
                    _ -> False

up :: V3
up = V3 0 0 1

base :: Panel
base = horizontal "base" 0

horizontal :: Text -> Double -> Panel
horizontal name z = Panel name [V3 (-1) (-1) z, V3 1 (-1) z, V3 1 1 z, V3 (-1) 1 z]

vertical :: Double -> Double -> Double -> Double -> Double -> Panel
vertical x lo hi bottom top = Panel "flap" [V3 x lo bottom, V3 x hi bottom, V3 x hi top, V3 x lo top]

report :: [(Text, Text)] -> [Panel] -> IO ContactCheck
report orders panels = case checkPanelContact up orders panels of
  Left err -> expectationFailure (show err) >> fail "invalid fixture"
  Right result -> pure result
