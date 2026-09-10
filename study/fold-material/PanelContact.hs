-- | Contact checks for the study's rigid convex panels: each panel is a flat
-- polygon, regardless of how finely the viewer subdivides it into triangles.
-- Convex means every segment between points in the panel stays in the panel;
-- see docs/glossary.md for the geometry vocabulary.
-- This is separate from FoldContact's curved-packet constraints because an
-- upright flap cannot be described as a height above the original sheet.
--
-- Two questions need separate answers. Panels can cross through each other in
-- 3D, or sit on the wrong side without crossing at all. For crossings, cut each
-- polygon by the other's plane and compare the resulting line intervals. Both
-- polygons must straddle the other's plane: merely meeting at a crease is legal.
-- For order, clip the upper polygon to the lower one's projected outline and
-- compare heights there. Only one polygon needs a height function, so a flap
-- at 90 degrees can still be checked against its horizontal base.
--
-- Orders name panels, not paper colours or camera-facing sides. They form a
-- partial order: unrelated flaps need no invented ranking. Coplanar overlap
-- without a known order is reported as unresolved. The tolerance is a distance
-- on this study's unit sheet. These are tests of individual zero-thickness
-- states, not constraints on the path between them or a finite-thickness solve.
module PanelContact
  ( PanelTag (..),
    ContactSpec (..),
    Panel (..),
    ContactCheck (..),
    ContactError (..),
    panelTolerance,
    checkPanelContact,
    contactPassed,
  )
where

import Control.Monad (unless)
import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.=))
import Data.List (tails)
import Data.Map.Strict qualified as M
import Data.Set qualified as S
import Data.Text (Text)
import Senbazuru.Explain (Explain (..))
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.Polygon (clipConvex, cross2, isConvex, signedArea)
import Senbazuru.Geometry.V3 (V3 (..), cross, polygonNormal)
import Senbazuru.Geometry.VectorSpace

data PanelTag = PanelTag {tagName :: !Text, tagAt :: !V2}
  deriving stock (Eq, Show)

instance FromJSON PanelTag where
  parseJSON = withObject "panel name and material point" $ \o -> do
    name <- o .: "name"
    point <- o .: "at"
    case point of
      [x, y] -> pure (PanelTag name (V2 x y))
      _ -> fail "panel at needs two material coordinates"

instance ToJSON PanelTag where
  toJSON (PanelTag name (V2 x y)) = object ["name" .= name, "at" .= [x, y]]

data ContactSpec = ContactSpec
  {orderDirection :: !V3, namedPanels :: ![PanelTag], panelOrders :: ![(Text, Text)]}
  deriving stock (Eq, Show)

instance FromJSON ContactSpec where
  parseJSON = withObject "panel contact requirements" $ \o -> do
    direction <- o .: "direction"
    case direction of
      [x, y, z] -> ContactSpec (V3 x y z) <$> o .: "panels" <*> o .: "orders"
      _ -> fail "contact direction needs three coordinates"

instance ToJSON ContactSpec where
  toJSON (ContactSpec (V3 x y z) panels orders) =
    object
      ["direction" .= [x, y, z], "panels" .= panels, "orders" .= orders]

data Panel = Panel {panelName :: !Text, panelCorners :: ![V3]}
  deriving stock (Eq, Show)

data ContactCheck = ContactCheck
  { checkedPanelPairs :: !Int,
    crossingPanels :: ![(Text, Text)],
    unorderedContacts :: ![(Text, Text)],
    reversedOrders :: ![(Text, Text, Double)],
    uncheckedOrders :: ![(Text, Text)]
  }
  deriving stock (Eq, Show)

instance ToJSON ContactCheck where
  toJSON result =
    object
      [ "passed" .= contactPassed result,
        "tolerance" .= panelTolerance,
        "checkedPanelPairs" .= checkedPanelPairs result,
        "crossingPanels" .= crossingPanels result,
        "unorderedContacts" .= unorderedContacts result,
        "reversedOrders" .= reversedOrders result,
        "uncheckedOrders" .= uncheckedOrders result
      ]

newtype ContactError = ContactError Text
  deriving stock (Eq, Show)

instance Explain ContactError where
  explain (ContactError message) = message

panelTolerance :: Double
panelTolerance = 1e-7

contactPassed :: ContactCheck -> Bool
contactPassed result =
  null (crossingPanels result)
    && null (unorderedContacts result)
    && null (reversedOrders result)
    && null (uncheckedOrders result)

-- | Each order is (lower, upper), along the supplied direction in model space.
-- Invalid declarations are errors; a valid declaration that the geometry fails
-- is a report, so the gallery can expose that failed state for inspection.
checkPanelContact :: V3 -> [(Text, Text)] -> [Panel] -> Either ContactError ContactCheck
checkPanelContact direction orders panels = do
  unless (finite direction && norm direction > 1e-12) (Left (ContactError "contact direction must be finite and nonzero"))
  let names = map panelName panels
      known = S.fromList names
  unless (not (null panels) && length names == S.size known && "" `notElem` names) $
    Left (ContactError "contact panels need unique, nonempty names")
  unless (all (\(a, b) -> S.member a known && S.member b known) orders) $
    Left (ContactError "panel order refers to an unknown panel")
  let reachable = closure (S.fromList orders)
  unless (all (\name -> S.notMember (name, name) reachable) names) $
    Left (ContactError "panel orders contain a cycle")
  prepared <- mapM prepare panels
  let indexed = M.fromList [(panelName p, plane) | (p, plane) <- zip panels prepared]
      pairs = [(a, b) | a : rest <- tails prepared, b <- rest]
      ordered a b = S.member (planeName a, planeName b) reachable || S.member (planeName b, planeName a) reachable
      checks =
        [ (a, b, orderGap axis lower upper) | (a, b) <- S.toList reachable, Just lower <- [M.lookup a indexed], Just upper <- [M.lookup b indexed]
        ]
      axis = unit direction
  pure
    ContactCheck
      { checkedPanelPairs = length pairs,
        crossingPanels = [(planeName a, planeName b) | (a, b) <- pairs, crosses a b],
        unorderedContacts = [(planeName a, planeName b) | (a, b) <- pairs, coplanarOverlap a b && not (ordered a b)],
        reversedOrders = [(a, b, negate gap) | (a, b, Just gap) <- checks, gap < negate panelTolerance],
        uncheckedOrders = [(a, b) | (a, b, Nothing) <- checks]
      }

closure :: S.Set (Text, Text) -> S.Set (Text, Text)
closure pairs =
  let next = pairs `S.union` S.fromList [(a, c) | (a, b) <- S.toList pairs, (b', c) <- S.toList pairs, b == b']
   in if next == pairs then pairs else closure next

data Plane = Plane {planeName :: !Text, corners :: ![V3], origin :: !V3, normal :: !V3}

prepare :: Panel -> Either ContactError Plane
prepare (Panel name points) = case points of
  p : _ -> do
    unless (all finite points && norm raw > 1e-12) (bad "needs finite corners and nonzero area")
    let n = unit raw
        projected = map (project n . (^-^ p)) points
    unless (all (\q -> abs (dot n (q ^-^ p)) <= panelTolerance) points) (bad "must be planar")
    unless (isConvex 1e-12 projected && abs (signedArea projected) > 1e-12) (bad "must be convex")
    pure (Plane name points p n)
  [] -> bad "needs corners"
  where
    raw = polygonNormal points
    bad message = Left (ContactError ("panel " <> name <> " " <> message))

finite :: V3 -> Bool
finite (V3 x y z) = all (\v -> not (isNaN v || isInfinite v)) [x, y, z]

unit :: V3 -> V3
unit v = (1 / norm v) *^ v

-- An orthonormal basis keeps distances in model units. Its handedness keeps
-- polygon winding meaningful even when a face points downwards.
project :: V3 -> V3 -> V2
project n p = V2 (dot u p) (dot v p)
  where
    u = unit (cross n (if abs (v3x n) < 0.9 then V3 1 0 0 else V3 0 1 0))
    v = cross n u

ring :: [a] -> [(a, a)]
ring xs = zip xs (drop 1 xs ++ take 1 xs)

signedDistance :: Plane -> V3 -> Double
signedDistance plane p = dot (normal plane) (p ^-^ origin plane)

straddles :: Plane -> Plane -> Bool
straddles a b = any (< negate panelTolerance) distances && any (> panelTolerance) distances
  where
    distances = map (signedDistance a) (corners b)

crosses :: Plane -> Plane -> Bool
crosses a b
  | not (straddles a b && straddles b a) = False
  | norm line < 1e-12 = False
  | otherwise = case (interval a b, interval b a) of
      (Just (lo, hi), Just (lo', hi')) -> min hi hi' - max lo lo' > panelTolerance
      _ -> False
  where
    line = cross (normal a) (normal b)
    direction = unit line
    interval plane polygon = case map (dot direction) (section plane polygon) of
      [] -> Nothing
      xs -> Just (minimum xs, maximum xs)

section :: Plane -> Plane -> [V3]
section plane polygon =
  [p | p <- corners polygon, abs (signedDistance plane p) <= panelTolerance]
    ++ [ p ^+^ ((dp / (dp - dq)) *^ (q ^-^ p)) | (p, q) <- ring (corners polygon), let dp = signedDistance plane p, let dq = signedDistance plane q, dp * dq < 0
       ]

coplanarOverlap :: Plane -> Plane -> Bool
coplanarOverlap a b =
  all ((<= panelTolerance) . abs . signedDistance a) (corners b)
    && all ((<= panelTolerance) . abs . signedDistance b) (corners a)
    && abs (signedArea (clipConvex (outline a) (outline b))) > 1e-12
  where
    outline = anticlockwise . map (project (normal a) . (^-^ origin a)) . corners

anticlockwise :: [V2] -> [V2]
anticlockwise ps = if signedArea ps < 0 then reverse ps else ps

-- Nothing means both panels stand parallel to the measuring direction: this
-- particular order cannot be checked as a height inequality. A zero gap means
-- either contact or no overlapping shadow; neither reverses the order.
orderGap :: V3 -> Plane -> Plane -> Maybe Double
orderGap axis lower upper
  | abs (dot (normal lower) axis) > 1e-8 = Just (minimum (0 : gaps lower upper))
  | abs (dot (normal upper) axis) > 1e-8 = Just (minimum (0 : map negate (gaps upper lower)))
  | otherwise = Nothing
  where
    gaps base moving =
      [signedDistance base p / dot (normal base) axis | p <- shadow base (corners moving)]
    shadow base moving = foldl clipSide moving sides
      where
        outline = anticlockwise (map (project axis) (corners base))
        sides = [(p, q) | (p, q) <- ring outline, norm (q ^-^ p) > 1e-12]
        clipSide ps (p, q) = clipBy (\r -> cross2 (q ^-^ p) (project axis r ^-^ p) / norm (q ^-^ p)) ps

-- Clip the actual 3D corners, not just their shadow: a vertical flap's two
-- ends have the same projected point but different heights that both matter.
clipBy :: (V3 -> Double) -> [V3] -> [V3]
clipBy distance ps = concatMap edge (ring ps)
  where
    snapped p = let d = distance p in if abs d < 1e-12 then 0 else d
    edge (p, q)
      | dp >= 0 && dq >= 0 = [q]
      | dp < 0 && dq < 0 = []
      | otherwise = let hit = p ^+^ ((dp / (dp - dq)) *^ (q ^-^ p)) in if dq >= 0 then [hit, q] else [hit]
      where
        dp = snapped p; dq = snapped q
