-- | Recheck and locate the costs of four saved equilibria without moving paper.
-- The two resolutions have different source-report schemas; HeldLayoutCosts
-- binds each to its original histories before any export. All geometry and
-- signed maps use the existing measurement/Diagram path. Browser code selects
-- artifacts and formats numbers only. Co-location of two costs is evidence
-- about these endpoints, not proof that one caused the other.
module HeldLayoutCostsGallery (writeHeldLayoutCosts) where

import BendLocations
import ClosedCrease
import Control.Monad (forM, unless, when)
import CoupledCrease (coupledReference)
import Data.Aeson (FromJSON, Value, eitherDecode, encode, object, (.=))
import Data.ByteString.Lazy qualified as BL
import Data.List (isPrefixOf)
import Data.Map.Strict qualified as M
import Data.Maybe (isJust, isNothing, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending
import HeldConfirmationGallery (Endpoint (..), compareEndpoints, writeEndpoint)
import HeldCosts
import HeldCostsGallery (costMap, differenceMap, heldChangeJson, plot)
import HeldEquilibrium
import HeldEquilibriumGallery (HeldState (..), measureHeldState)
import HeldLayoutCosts
import HeldRefinement (refinementWeight)
import MatchedEnergy
import MatchedEnergyGallery (groupReport)
import OuterContinuation (agreeMeasurements)
import PrescribedBend
import Senbazuru.Explain (Explain (..))
import Senbazuru.Fold.Types (FoldFile (..))
import Senbazuru.Geometry (V2 (..))
import System.Directory (canonicalizePath, createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath (splitDirectories, (</>))

data Input = Input
  { inputKey :: String,
    inputCase :: HeldCase,
    inputBytes :: BL.ByteString,
    inputHistory :: Value,
    inputEndpoint :: Endpoint,
    inputBends :: [LocatedBend],
    inputLengths :: [LocatedLength]
  }

writeHeldLayoutCosts :: FilePath -> FilePath -> IO ()
writeHeldLayoutCosts source destination = do
  let output = destination </> "held-layout-costs"
  src <- splitDirectories <$> canonicalizePath source
  dst <- splitDirectories <$> canonicalizePath output
  when (src `isPrefixOf` dst || dst `isPrefixOf` src) (die "held-layout-costs source and output directories must not overlap")
  bytes <- BL.readFile (source </> "checks.json")
  originalBytes <- BL.readFile (source </> "source-checks.json")
  document <- decode bytes
  original <- decode originalBytes
  inputs <- forM layoutCases $ \(key, layout, budget) -> do
    c <- checked (heldCase layout budget)
    let fixture = heldFixture c
        stem = key <> if budget == Triangles512 then "-after" else ""
    (history, saved) <- checked (layoutRecord (T.pack key) layout budget c document original)
    when (budget == Triangles512) $ do
      single <- BL.readFile (source </> key <> "-checks.json") >>= decode
      checked (agreeMeasurements history single)
    singleState <- BL.readFile (source </> stem <> ".json") >>= decode
    checked (agreeMeasurements saved singleState)
    raw <- BL.readFile (source </> stem <> ".fold")
    file <- decode raw
    mesh <- checked (savedBendMesh fixture (keyFrame file))
    measured <- measureHeldState fixture mesh
    checked (agreeMeasurements saved (heldStateReport measured))
    unless (heldStateValid measured) (die "saved layout endpoint failed fresh paper checks")
    bends <- checked (locateBends (coupledReference fixture) {closedMesh = mesh})
    lengths <- checked (locateLengths mesh (probeEdges (heldStateCost measured)))
    pure (Input key c raw history (Endpoint key mesh measured True) bends lengths)
  let get key = case [i | i <- inputs, inputKey i == key] of [i] -> pure i; _ -> die "missing unique layout endpoint"
  pairs <- forM [(size, upper, panel) | size <- [256, 512 :: Int], (upper, panel) <- [(False, "lower" :: Text), (True, "upper")]] $ \(size, upper, panel) -> do
    a <- get ("uniform-" <> show size)
    b <- get ("whole-" <> show size)
    let passive i = [h | h <- inputBends i, measuredUpper (locatedMeasure h) == upper, hingeRole (measuredHinge (locatedMeasure h)) == PanelBend]
        lengths i = filter ((== if upper then UpperLength else LowerLength) . lengthSide) (inputLengths i)
    bs <- checked (compareBends (passive a) (passive b))
    ls <- checked (compareLengths (lengths a) (lengths b))
    pure (size, panel, a, b, bs, ls)
  let bendTop = maximum (1e-12 : [abs (edgeDelta c) | (_, _, _, _, bs, _) <- pairs, c <- bs])
      lengthTop = maximum (1e-12 : [abs (lengthDelta c) | (_, _, _, _, _, ls) <- pairs, c <- ls])
      bendTotal = maximum (1e-12 : [sum (map (bendEnergy . side) bs) | (_, _, _, _, bs, _) <- pairs, side <- [oldBend, newBend]])
      lengthTotal = maximum (1e-12 : [sum (map (maybe 0 lengthCost . side) ls) | (_, _, _, _, _, ls) <- pairs, side <- [oldLength, newLength]])
  createDirectoryIfMissing True output
  BL.writeFile (output </> "source-checks.json") bytes
  BL.writeFile (output </> "source-confirmation-checks.json") originalBytes
  endpoints <- forM inputs $ \i -> do
    let e = inputEndpoint i
    _ <- writeEndpoint output (heldFixture (inputCase i)) "Unchanged saved endpoint" e
    BL.writeFile (output </> inputKey i <> ".fold") (inputBytes i)
    pure (object ["id" .= inputKey i, "history" .= inputHistory i, "state" .= heldStateReport (endpointState e), "lengthEdges" .= map lengthJson (inputLengths i), "lengthAccounting" .= [object ["side" .= show side, "count" .= length rows, "energy" .= sum (map lengthCost rows)] | side <- [LowerLength, UpperLength, SharedLength], let rows = filter ((== side) . lengthSide) (inputLengths i)]])
  reports <- forM pairs $ \(size, panel, a, b, bs, ls) -> do
    let key = show size <> "-" <> T.unpack panel
        write suffix = TIO.writeFile (output </> key <> "-" <> suffix <> ".svg")
        bendRows pick = [(locatedDistance h, measuredEnergy (locatedMeasure h)) | c <- bs, Just h <- [pick c]]
        lengthRows pick = [(lengthDistance h, lengthCost h) | c <- ls, Just h <- [pick c]]
        curves title top before after = plot title top False [("#a67832", cumulative before), ("#306575", cumulative after)] []
    write "passive-map" (differenceMap bendTop bs)
    write "length-map" (costMap lengthTop [(lengthFrom h, lengthTo h, lengthDelta c) | c <- ls, let h = lengthLocation c])
    write "passive-cumulative" (curves "Cumulative passive cost" bendTotal (bendRows oldBend) (bendRows newBend))
    write "length-cumulative" (curves "Cumulative length penalty" lengthTotal (lengthRows oldLength) (lengthRows newLength))
    metrics <- compareEndpoints (inputEndpoint a) (inputEndpoint b)
    let regions = [minBound .. maxBound]
        directions = ["Transverse", "Lengthwise", "Diagonal"]
        bendGroup r d = groupReport (T.pack (show r) <> "/" <> d) [c | c <- bs, heldRegion (locatedDistance (changeLocation c)) == r, edgeDirection (changeLocation c) == d]
        lengthGroup r d = lengthReport (T.pack (show r) <> "/" <> d) [c | c <- ls, heldRegion (lengthDistance (lengthLocation c)) == r, lengthDirection (lengthLocation c) == d]
        report =
          object
            [ "id" .= key,
              "triangles" .= size,
              "panel" .= panel,
              "before" .= inputKey a,
              "after" .= inputKey b,
              "metrics" .= metrics,
              "passive" .= object ["totals" .= groupReport "all" bs, "regions" .= [groupReport (T.pack (show r)) [c | c <- bs, heldRegion (locatedDistance (changeLocation c)) == r] | r <- regions], "directions" .= [groupReport d [c | c <- bs, edgeDirection (changeLocation c) == d] | d <- directions], "cells" .= [bendGroup r d | r <- regions, d <- directions], "edges" .= map heldChangeJson bs],
              "length" .= object ["totals" .= lengthReport "all" ls, "regions" .= [lengthReport (T.pack (show r)) [c | c <- ls, heldRegion (lengthDistance (lengthLocation c)) == r] | r <- regions], "directions" .= [lengthReport d [c | c <- ls, lengthDirection (lengthLocation c) == d] | d <- directions], "cells" .= [lengthGroup r d | r <- regions, d <- directions], "edges" .= map lengthChangeJson ls]
            ]
    BL.writeFile (output </> key <> "-checks.json") (encode report)
    pure report
  let report = object ["gallery" .= ("held-layout-costs" :: Text), "solverRun" .= False, "repairRun" .= False, "coordinatesChanged" .= False, "lengthWeight" .= refinementWeight, "passiveEdgeScale" .= bendTop, "lengthEdgeScale" .= lengthTop, "passiveCumulativeScale" .= bendTotal, "lengthCumulativeScale" .= lengthTotal, "endpoints" .= endpoints, "comparisons" .= reports]
  BL.writeFile (output </> "checks.json") (encode report)
  template <- TIO.readFile "study/fold-material/held-layout-costs.html"
  TIO.writeFile (destination </> "held-layout-costs.html") (T.replace "/*HELD_LAYOUT_COSTS*/null" (TE.decodeUtf8 (BL.toStrict (encode report))) template)
  putStrLn "Wrote held-layout-costs.html from four unchanged endpoints. No optimizer or repair ran."

cumulative :: [(Double, Double)] -> [V2]
cumulative entries = V2 0 0 : go 0 (M.toAscList (M.fromListWith (+) entries))
  where
    go total [] = [V2 0.5 total]
    go total ((x, e) : xs) = V2 x total : V2 x (total + e) : go (total + e) xs

lengthJson :: LocatedLength -> Value
lengthJson h = object ["vertices" .= [a, b], "from" .= xy (lengthFrom h), "to" .= xy (lengthTo h), "side" .= show (lengthSide h), "distance" .= lengthDistance h, "region" .= show (heldRegion (lengthDistance h)), "direction" .= lengthDirection h, "rest" .= edgeRest e, "actual" .= edgeActual e, "error" .= err, "relativeError" .= (err / edgeRest e), "energy" .= lengthCost h]
  where
    e = lengthMeasure h; (a, b) = edgeIds e; err = edgeActual e - edgeRest e; xy (V2 u v) = [u, v]

lengthChangeJson :: LengthChange -> Value
lengthChangeJson c = object ["location" .= lengthJson (lengthLocation c), "before" .= fmap lengthJson (oldLength c), "after" .= fmap lengthJson (newLength c), "membership" .= membership, "direction" .= lengthDirection (lengthLocation c), "delta" .= lengthDelta c]
  where
    membership | isNothing (oldLength c) = "Added" | isNothing (newLength c) = "Removed" | otherwise = "Shared" :: Text

lengthReport :: Text -> [LengthChange] -> Value
lengthReport name cs = object ["name" .= name, "before" .= a, "after" .= b, "delta" .= (b - a), "percent" .= (if a <= 1e-12 then Nothing else Just (100 * (b - a) / a)), "sharedCount" .= length shared, "addedCount" .= length added, "removedCount" .= length removed, "sharedDelta" .= sum (map lengthDelta shared), "addedEnergy" .= sum (map lengthDelta added), "removedEnergy" .= sum (map lengthDelta removed), "accountingResidual" .= (sum (map lengthDelta cs) - (b - a)), "beforeMaxRelativeError" .= worst (mapMaybe oldLength cs), "afterMaxRelativeError" .= worst (mapMaybe newLength cs)]
  where
    a = sum [lengthCost h | c <- cs, Just h <- [oldLength c]]
    b = sum [lengthCost h | c <- cs, Just h <- [newLength c]]
    shared = filter (\c -> isJust (oldLength c) && isJust (newLength c)) cs
    added = filter (isNothing . oldLength) cs
    removed = filter (isNothing . newLength) cs
    worst hs = maximum (0 : [abs (edgeActual e / edgeRest e - 1) | h <- hs, let e = lengthMeasure h])

decode :: (FromJSON a) => BL.ByteString -> IO a
decode = either die pure . eitherDecode

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
