-- | Shared readiness gates for alternative constructions of a body seed.
-- A smaller geometric construction error is not material acceptance. Both
-- galleries must apply the same inherited order, discovered barrier-domain,
-- exact-hold/length and strict static-contact checks. A failed reference means
-- its dependent checks were not evaluated, not that the barrier solver failed.
module BodyInitializationCheck (probeInitialization) where

import BodyInitialization
import BodyPatch
import BodyPatchSubdivision (seedPassed)
import CorrectionSweep qualified as Motion
import CraneSpread
import Data.Aeson (Value, object, (.=))
import Data.Either (isRight)
import Data.IntMap.Strict qualified as IM
import Data.Set qualified as S
import Data.Text (Text)
import Data.Text qualified as T
import FoldContact (ContactRow (..))
import LocalContactDiscovery qualified as Local
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Types (FaceId)
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Surface
import SurfaceContact qualified as C

-- All gates are evaluated independently for the report. A reference failure
-- skips its barrier-domain evaluation, never the inherited or static checks.
probeInitialization :: BodyPatch -> C.OrderedContact -> MaterialMesh -> Either InitializationError (Bool, Value)
probeInitialization study model mesh = do
  let fixture = patchSpread study
  geometry <- adapt (seedPassed study mesh)
  ws <- adapt (C.contactWitnesses model mesh)
  let topology = IM.fromList (zip [0 ..] (triangles mesh))
      vertices i = case IM.lookup i topology of Just (a, b, c) -> [a, b, c]; Nothing -> []
      disjoint w = let (a, b) = C.witnessTriangles w in all (`notElem` vertices b) (vertices a)
      gaps = [contactGap (C.witnessRow w) | w <- ws, disjoint w]
      gapPass = all (> initializationClearance) gaps
      reference = Local.discoverLocalReference initializationClearance 0.03 (V3 0 0 1) mesh
      barrier = case reference of Left _ -> Nothing; Right ref -> Just (Local.localBarrierContacts 0.001 ref mesh)
      barrierPass = case barrier of Just (Right rows) -> all finiteRow rows; _ -> False
      owners = IM.fromList (zip [0 ..] (refinedPanels (spreadRefined fixture)))
      orders = spreadContactOrders fixture
      compatible ref = all (\(a, b) -> case (IM.lookup a owners, IM.lookup b owners) of (Just pa, Just pb) -> not (pa /= pb && reachable orders pb pa); _ -> False) (Local.localReferenceOrders ref)
      orderPass = either (const False) compatible reference
      static = Motion.prepareCorrection mesh mesh >>= Motion.checkCorrection Motion.defaultCorrectionSettings
      staticPass = case static of Right check -> Motion.correctionOutcome check == Motion.CorrectionClear; _ -> False
      passed = geometry && gapPass && isRight reference && barrierPass && orderPass && staticPass
      details = object ["passed" .= passed, "geometryPassed" .= geometry, "clearancePassed" .= gapPass, "minimumDisjointHeightGap" .= (if null gaps then Nothing else Just (minimum gaps)), "disjointWitnessCount" .= length gaps, "referencePassed" .= isRight reference, "referenceFailure" .= either (Just . explain) (const Nothing) reference, "learnedOrders" .= either (const ([] :: [[Int]])) (map (\(a, b) -> [a, b]) . Local.localReferenceOrders) reference, "inheritedOrderCompatible" .= orderPass, "barrierDomainPassed" .= barrierPass, "barrierFailure" .= case barrier of Nothing -> Just ("not evaluated: no local reference" :: Text); Just rows -> either (Just . explain) (const Nothing) rows, "strictStaticPassed" .= staticPass, "strictStaticResult" .= either explain (T.pack . show . Motion.correctionOutcome) static]
  pure (passed, details)
  where
    finiteRow row = finite (contactGap row) && all (\(_, V3 a b c) -> all finite [a, b, c]) (contactGradient row)
    finite x = not (isNaN x || isInfinite x)

reachable :: [(FaceId, FaceId)] -> FaceId -> FaceId -> Bool
reachable orders from target = go S.empty [from]
  where
    go _ [] = False
    go seen (p : rest) | p == target = True | S.member p seen = go seen rest | otherwise = go (S.insert p seen) ([b | (a, b) <- orders, a == p] ++ rest)

adapt :: (Explain e) => Either e a -> Either InitializationError a
adapt = either (Left . InitializationError . explain) Right
