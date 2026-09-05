-- |
-- Tests for turning FOLD's stacking relations into a drawing order.
--
-- The property worth stating loudest is that the answer depends on where you
-- are standing. @faceOrders@ describes the paper, not the picture: it says a
-- face is on the side another face's normal points to, and whether that is
-- nearer the viewer or further from them is a separate question. Reverse the
-- viewing direction and the whole stack must reverse with it.
module Senbazuru.Origami.LayersSpec (spec) where

import Senbazuru.Fold.Query (Face (..))
import Senbazuru.Fold.Types (FaceId (..), FaceOrder (..), Stacking (..), VertexId (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Layers
import Test.Hspec

-- | A unit square in the plane @z = 0@ at the given height, listed
-- counterclockwise so that its normal is @+z@.
facingUp :: Int -> Double -> Face
facingUp i z =
  Face
    { faceId = FaceId i,
      faceVertexIds = map VertexId [0, 1, 2, 3],
      faceCorners = [V3 0 0 z, V3 1 0 z, V3 1 1 z, V3 0 1 z]
    }

-- | The same square listed the other way round, so its normal is @-z@.
facingDown :: Int -> Double -> Face
facingDown i z = (facingUp i z) {faceCorners = reverse (faceCorners (facingUp i z))}

above, below :: Int -> Int -> FaceOrder
above f g = FaceOrder (FaceId f) (FaceId g) Above
below f g = FaceOrder (FaceId f) (FaceId g) Below

fromAbove, fromBelow :: V3
fromAbove = V3 0 0 1
fromBelow = V3 0 0 (-1)

ids :: [Int] -> [FaceId]
ids = map FaceId

spec :: Spec
spec = do
  describe "which face is drawn last" $ do
    it "draws the face on top last, seen from above" $
      paintOrder fromAbove [facingUp 0 0, facingUp 1 0] [above 1 0]
        `shouldBe` Right (ids [0, 1])

    it "draws it first, seen from below" $
      -- The same file, the same stacking, the other side of the paper. Nothing
      -- about the model changed; the picture is upside down.
      paintOrder fromBelow [facingUp 0 0, facingUp 1 0] [above 1 0]
        `shouldBe` Right (ids [1, 0])

    it "reads the sign against the normal of the second face, not the first" $ do
      -- [f, g, s] is relative to g's normal. Here g is face 0 and it faces
      -- down, so "above" points away from a viewer overhead.
      paintOrder fromAbove [facingDown 0 0, facingUp 1 0] [above 1 0]
        `shouldBe` Right (ids [1, 0])
      -- Turning the *first* face over changes nothing, because its normal is
      -- not what the sign is measured against.
      paintOrder fromAbove [facingUp 0 0, facingDown 1 0] [above 1 0]
        `shouldBe` Right (ids [0, 1])

    it "treats below as the mirror of above" $
      paintOrder fromAbove [facingUp 0 0, facingUp 1 0] [below 1 0]
        `shouldBe` Right (ids [1, 0])

  describe "what it leaves alone" $ do
    it "keeps file order where nothing is ordered" $
      -- A file that orders no pair is not withholding information. Faces that
      -- do not overlap cannot obscure each other, and that is what FOLD says by
      -- leaving the pair out.
      paintOrder fromAbove [facingUp 0 0, facingUp 1 0, facingUp 2 0] []
        `shouldBe` Right (ids [0, 1, 2])

    it "ignores an entry that explicitly says unordered" $
      paintOrder fromAbove [facingUp 0 0, facingUp 1 0] [FaceOrder (FaceId 1) (FaceId 0) Unordered]
        `shouldBe` Right (ids [0, 1])

    it "ignores a face seen exactly edge on" $
      -- Its normal is perpendicular to the line of sight, so "above" separates
      -- nothing along it. The relation still holds in the model; it just says
      -- nothing about what covers what, and inventing an order from it would be
      -- making something up.
      paintOrder (V3 1 0 0) [facingUp 0 0, facingUp 1 0] [above 1 0]
        `shouldBe` Right (ids [0, 1])

    it "settles a partial order without needing the rest" $ do
      -- Two constraints on three faces, which is what a real file gives: enough
      -- to fix the pairs that overlap and silent about the pair that does not.
      let faces = [facingUp i 0 | i <- [0 .. 2]]
      paintOrder fromAbove faces [above 2 0, above 1 0] `shouldBe` Right (ids [0, 1, 2])
      paintOrder fromAbove faces [below 2 0, below 1 0] `shouldBe` Right (ids [1, 2, 0])

  describe "orderings that cannot be drawn" $ do
    it "refuses a stack that is in front of itself" $
      paintOrder fromAbove [facingUp 0 0, facingUp 1 0, facingUp 2 0] [above 1 0, above 2 1, above 0 2]
        `shouldBe` Left (CyclicStacking (FaceId 0))

    it "refuses an order naming a face that is not there" $
      paintOrder fromAbove [facingUp 0 0] [above 1 0]
        `shouldBe` Left (UnknownFace (FaceId 1))
