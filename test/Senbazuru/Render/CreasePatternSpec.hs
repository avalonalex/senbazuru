-- |
-- Tests for the rendering policy that used to live in the executable.
--
-- 'defaultBasisFor' decides which way to look at geometry nobody has specified
-- a view for. It sat in @app\/@ originally, where the test suite cannot reach
-- it, and a bug went unnoticed for exactly that reason: the first version keyed
-- off @frame_classes@ and sheared every flat-folded model.
module Senbazuru.Render.CreasePatternSpec (spec) where

import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Render.Camera (isometric, topDown)
import Senbazuru.Render.CreasePattern (defaultBasisFor)
import Test.Hspec

spec :: Spec
spec = describe "defaultBasisFor" $ do
  it "views a flat sheet from above" $
    defaultBasisFor [V3 0 0 0, V3 1 0 0, V3 1 1 0, V3 0 1 0] `shouldBe` topDown

  it "views something with relief isometrically" $
    defaultBasisFor [V3 0 0 0, V3 1 0 0, V3 1 1 0.5] `shouldBe` isometric

  it "views a FLAT-FOLDED model from above, not isometrically" $
    -- The case the first version got wrong. A folded form need not be 3D: the
    -- traditional crane folds flat, so its folded frame lies in a plane, and an
    -- isometric camera would shear a correct picture into a wrong one. Keying
    -- off frame_classes could not tell these apart; the coordinates can.
    defaultBasisFor [V3 0 0 0, V3 0.5 0 0, V3 0.5 0.5 0] `shouldBe` topDown

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
