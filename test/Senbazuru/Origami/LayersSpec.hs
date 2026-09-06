-- |
-- Tests for turning FOLD's stacking relations into a drawing order.
--
-- The property worth stating loudest is that the answer depends on where you
-- are standing. @faceOrders@ describes the paper, not the picture: it says a
-- face is on the side another face's normal points to, and whether that is
-- nearer the viewer or further from them is a separate question. Reverse the
-- viewing direction and the whole stack must reverse with it.
module Senbazuru.Origami.LayersSpec (spec) where

import Senbazuru.Fold.Query (Face (..), FoldError (..))
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

-- | @n@ coplanar squares, for the questions that are about the orders rather
-- than about the geometry.
squares :: Int -> [Face]
squares n = [facingUp i 0 | i <- [0 .. n - 1]]

-- | The depths of @n@ 'squares' under the given orders, seen from above.
depthsOf :: Int -> [FaceOrder] -> Either FoldError [(FaceId, Int)]
depthsOf n = layerDepths fromAbove (squares n)

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

  describe "faces the file does not order" $ do
    it "draws the furthest one first" $ do
      -- Two faces in different planes need no faceOrders entry -- they do not
      -- overlap, so neither is above the other -- and can still cover the same
      -- patch of page once projected. File order says nothing about which is
      -- nearer; depth does.
      paintOrder fromAbove [facingUp 0 5, facingUp 1 0] []
        `shouldBe` Right (ids [1, 0])
      paintOrder fromAbove [facingUp 0 0, facingUp 1 5] []
        `shouldBe` Right (ids [0, 1])

    it "draws it last from the other side" $
      -- The same two faces, the other side of the model.
      paintOrder fromBelow [facingUp 0 5, facingUp 1 0] []
        `shouldBe` Right (ids [0, 1])

    it "keeps file order between faces at the same depth" $
      -- Coplanar faces have nothing to choose between them, so the answer has to
      -- be reproducible rather than merely arbitrary: goldens depend on it.
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

  describe "orderings a file may write more than one way" $ do
    it "says the same thing twice without drawing anything twice" $
      -- Kahn's algorithm counts edges, so a repeated constraint decrements its
      -- target's count twice and frees it twice: the face comes out of the sort
      -- more than once, and the extra copies pad the output enough that a real
      -- cycle can slip past the "did everything come out?" check.
      paintOrder fromAbove [facingUp 0 0, facingUp 1 0] [above 1 0, above 1 0]
        `shouldBe` Right (ids [0, 1])

    it "treats above and below written the other way round as one constraint" $
      -- [f, g, +1] and [g, f, -1] say the same thing, and a file may carry both.
      paintOrder fromAbove [facingUp 0 0, facingUp 1 0] [above 1 0, below 0 1]
        `shouldBe` Right (ids [0, 1])

    it "still finds a cycle behind a pile of duplicates" $
      paintOrder
        fromAbove
        [facingUp i 0 | i <- [0 .. 4]]
        [above 1 0, above 1 0, above 1 0, above 4 3, above 3 4]
        `shouldBe` Left (ImpossibleStacking (FaceId 3))

  describe "orderings that cannot be drawn" $ do
    it "refuses a stack that is in front of itself" $
      paintOrder fromAbove [facingUp 0 0, facingUp 1 0, facingUp 2 0] [above 1 0, above 2 1, above 0 2]
        `shouldBe` Left (ImpossibleStacking (FaceId 0))

    it "refuses an order naming a face that is not there" $
      paintOrder fromAbove [facingUp 0 0] [above 1 0]
        `shouldBe` Left (FaceOrderOutOfRange (FaceId 1) 1)

    it "refuses to measure against a face with no area" $ do
      -- Its normal is the zero vector, so "above" and "below" have no direction
      -- to mean anything in. Treating that as edge-on would silently discard a
      -- constraint the file actually stated.
      let sliver = (facingUp 0 0) {faceCorners = [V3 0 0 0, V3 1 1 0, V3 2 2 0]}
      paintOrder fromAbove [sliver, facingUp 1 0] [above 1 0]
        `shouldBe` Left (FaceWithoutNormal (FaceId 0))

  describe "how deep in the stack each face lies" $ do
    it "numbers a stack from the bottom up" $
      -- Four squares folded onto one another, every pair recorded, which is
      -- what the quarter fold produces.
      depthsOf
        4
        [above 1 0, above 2 0, above 3 0, above 2 1, above 3 1, above 3 2]
        `shouldBe` Right [(FaceId 0, 0), (FaceId 1, 1), (FaceId 2, 2), (FaceId 3, 3)]

    it "counts the longest chain below a face, not the faces below it" $ do
      -- 0 under 1 under 2, with no entry saying 2 is over 0 -- which is what a
      -- file writes when 2 has slid clear of 0 and the two no longer share any
      -- paper. Face 2 is still the third layer, because getting to it means
      -- passing through 1 and then 0.
      depthsOf 3 [above 1 0, above 2 1]
        `shouldBe` Right [(FaceId 0, 0), (FaceId 1, 1), (FaceId 2, 2)]
      -- Counting what is under it would have made it the second.
      fmap (lookup (FaceId 2)) (depthsOf 3 [above 1 0, above 2 1])
        `shouldNotBe` Right (Just 1)

    it "puts faces that overlap nothing all in the same layer" $
      -- A crease pattern is exactly this: faces that abut and never overlap, so
      -- there is nothing to step apart and an offset view of one is the
      -- ordinary picture.
      depthsOf 4 [] `shouldBe` Right [(FaceId i, 0) | i <- [0 .. 3]]

    it "turns the stack over with the viewer" $
      -- The same model from underneath: what was the bottom layer is now the
      -- top one, and the depths say so.
      layerDepths fromBelow (squares 3) [above 1 0, above 2 1, above 2 0]
        `shouldBe` Right [(FaceId 2, 0), (FaceId 1, 1), (FaceId 0, 2)]

    it "refuses a stack with no order at all, as painting does" $
      -- A twist: every pair is fine and the circle is not. An offset view needs
      -- one number per face and there is none to give, which is the same
      -- refusal 'paintOrder' makes and for the same reason.
      layerDepths fromAbove (squares 3) [above 1 0, above 2 1, above 0 2]
        `shouldBe` Left (ImpossibleStacking (FaceId 0))

  describe "which side of the paper a face shows" $ do
    it "shows the top side to a viewer the normal points at" $ do
      showsTopSide fromAbove (facingUp 0 0) `shouldBe` True
      showsTopSide fromBelow (facingUp 0 0) `shouldBe` False

    it "turns over with the face" $ do
      -- A flap folded over shows its back, which is the whole reason the two
      -- sides of origami paper are different colours.
      showsTopSide fromAbove (facingDown 0 0) `shouldBe` False
      showsTopSide fromBelow (facingDown 0 0) `shouldBe` True
