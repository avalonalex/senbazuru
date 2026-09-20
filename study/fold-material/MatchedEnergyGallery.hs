-- | A saved-data-only view of the matched-hold refinement control. The two
-- rule labels contain the same unloaded experiment, so verify both archives
-- but compare four unique endpoints. All coordinates are copied unchanged;
-- writeOuterState only measures and exports them, never solves or repairs.
-- MatchedEnergy explains why edge contributions are discrete accounting,
-- rather than continuous energy densities or independent material effects.
module MatchedEnergyGallery (writeMatchedEnergy, groupReport, changeJson) where

import BandBoundary (BoundaryRule (..))
import BendLocations
import BendLocationsGallery (plotPoint, plotSvg, rowJson)
import ClosedCrease
import Control.Monad (forM, forM_, unless, when)
import CoupledCrease
import CreasePairContact
import Data.Aeson (Value, eitherDecode, encode, object, withObject, (.:), (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.Types (parseEither)
import Data.ByteString.Lazy qualified as BL
import Data.List (isPrefixOf)
import Data.Map.Strict qualified as M
import Data.Maybe (isJust, isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending
import MatchedEnergy
import OuterContinuation (agreeMeasurements)
import OuterStrip
import OuterStripGallery (writeOuterState)
import PrescribedBend
import Senbazuru.Diagram
import Senbazuru.Explain (Explain (..), num)
import Senbazuru.Fold.Types (FoldFile (..))
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Render.Svg
import System.Directory (canonicalizePath, createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath (splitDirectories, (</>))
import UnequalCrease (UnequalControl (..))

writeMatchedEnergy :: FilePath -> FilePath -> IO ()
writeMatchedEnergy source destination = do
  let output = destination </> "matched-energy"
  sourcePath <- splitDirectories <$> canonicalizePath source
  outputPath <- splitDirectories <$> canonicalizePath output
  when (sourcePath `isPrefixOf` outputPath || outputPath `isPrefixOf` sourcePath) (die "energy output and source directories must not overlap")
  bytes <- BL.readFile (source </> "checks.json")
  document <- either die pure (eitherDecode bytes)
  -- Validate both labelled inputs before writing. The rules only differ for
  -- loaded controls; their matched fixtures have no imposed band spring.
  inputs <- forM outerMeshes $ \(choice, key, label) -> do
    fixture <- checked (outerFixture choice OriginalTurns MatchedHolds)
    original <- checked (matchedRecord choice (T.pack key) "original" fixture document)
    fractional <- checked (matchedRecord choice (T.pack key) "fractional" fixture document)
    loaded <- forM ["original", "fractional"] $ \rule -> do
      let name = "matched-" <> key <> "-" <> rule <> "-after.fold"
      raw <- BL.readFile (source </> name)
      file <- either die pure (eitherDecode raw)
      mesh <- checked (savedBendMesh fixture (keyFrame file))
      pure (name, raw, mesh)
    case loaded of
      [(_, _, a), (_, _, b)] -> unless (a == b) (die "matched rule archives contain different geometry")
      _ -> die "expected both matched rule archives"
    forM_ ["solve", "states"] $ \keyName -> do
      a <- field keyName original
      b <- field keyName fractional
      checked (agreeMeasurements a b)
    pure (choice, key, label, fixture, original, loaded)
  createDirectoryIfMissing True output
  BL.writeFile (output </> "source-checks.json") bytes
  endpoints <- forM inputs $ \(choice, key, label, fixture, original, loaded) -> case loaded of
    (_, raw, mesh) : _ -> do
      audit <- checked (auditPairContact (closedOwners (coupledReference fixture)) mesh)
      let scale = maximum [1e-8, fromRational (abs (pairMinimum audit)), fromRational (abs (pairMaximum audit))]
      (valid, rows, report, _) <- writeOuterState output choice MatchedHolds fixture scale key label mesh audit
      old <- field "states" original >>= field "after"
      checked (agreeMeasurements old report)
      unless valid (die "saved matched endpoint failed fresh geometry checks")
      BL.writeFile (output </> key <> ".fold") raw
      forM_ loaded $ \(name, content, _) -> BL.writeFile (output </> name) content
      let saved = object ["id" .= key, "label" .= label, "duplicateRuleChecked" .= True, "sourcePassed" .= True, "sourceConverged" .= True, "state" .= report]
      pure (choice, key, rows, saved)
    _ -> die "missing matched endpoint"
  let lookupRows choice = case [(key, rows) | (mesh, key, rows, _) <- endpoints, mesh == choice] of
        [r] -> pure r
        _ -> die "missing unique matched mesh"
      passive upper = filter (\h -> measuredUpper (locatedMeasure h) == upper && hingeRole (measuredHinge (locatedMeasure h)) == PanelBend)
  pairs <- forM [(a, b, upper, panel) | (a, b) <- outerPairs, (upper, panel) <- [(False, "lower" :: Text), (True, "upper")]] $ \(a, b, upper, panel) -> do
    (ka, allA) <- lookupRows a
    (kb, allB) <- lookupRows b
    let ra = passive upper allA
        rb = passive upper allB
    changes <- checked (compareBends ra rb)
    pure (ka, kb, panel, ra, rb, changes)
  -- One signed scale across every pair and both panels; no auto-contrast
  -- makes the tiny outer-strip contributions look as large as the interior.
  let deltaTop = maximum (1e-12 : [abs (edgeDelta c) | (_, _, _, _, _, cs) <- pairs, c <- cs])
      energyTop = maximum (1e-12 : [sum (map (measuredEnergy . locatedMeasure) rs) | (_, _, _, a, b, _) <- pairs, rs <- [a, b]])
      rateTop = maximum (1e-12 : [abs x | (_, _, _, a, b, _) <- pairs, h <- a ++ b, Just x <- [locatedRate h]])
  reports <- forM pairs $ \(ka, kb, panel, a, b, changes) -> do
    let stem = ka <> "-" <> kb <> "-" <> T.unpack panel
        write suffix = TIO.writeFile (output </> stem <> "-" <> suffix <> ".svg")
        totals = groupReport "all" changes
        bins = M.toAscList (M.fromListWith (+) [(locatedDistance (changeLocation c), edgeDelta c) | c <- changes])
        -- Site totals may include two width segments, so use a separate,
        -- explicitly labelled global scale for that aggregated plot.
        siteTop = maximum (1e-12 : [abs x | (_, _, _, _, _, cs) <- pairs, x <- M.elems (M.fromListWith (+) [(locatedDistance (changeLocation c), edgeDelta c) | c <- cs])])
        siteBars = [Polyline (solid (Colour (if d >= 0 then "#a64732" else "#287b87")) 2) [plotPoint siteTop x 0, plotPoint siteTop x d] | (x, d) <- bins]
        rateTrace rs = [V2 x mean | (x, mean, _, _) <- transverseRates rs]
    write "map" (differenceMap deltaTop changes)
    write "sites" (plotSvg "Energy change at each distance" siteTop True [] siteBars)
    write "cumulative" (plotSvg "Cumulative passive energy" energyTop False [("#a67832", cumulativeEnergy a), ("#306575", cumulativeEnergy b)] [])
    write "rates" (plotSvg "Mean transverse turn / material spacing" rateTop True [("#a67832", rateTrace a), ("#306575", rateTrace b)] [])
    let report =
          object
            [ "id" .= stem,
              "before" .= ka,
              "after" .= kb,
              "panel" .= panel,
              "totals" .= totals,
              "regions" .= [groupReport (T.pack (show r)) [c | c <- changes, locatedRegion (changeLocation c) == r] | r <- [minBound .. maxBound]],
              "directions" .= [groupReport d [c | c <- changes, edgeDirection (changeLocation c) == d] | d <- ["Transverse", "Lengthwise", "Diagonal"]],
              "sites" .= [object ["distance" .= x, "delta" .= d] | (x, d) <- bins],
              "edges" .= map changeJson changes
            ]
    BL.writeFile (output </> stem <> "-checks.json") (encode report)
    pure report
  let report = object ["gallery" .= ("matched-energy" :: Text), "solverRun" .= False, "coordinatesChanged" .= False, "uniqueEndpoints" .= (4 :: Int), "checkedArchives" .= (8 :: Int), "edgeDeltaScale" .= deltaTop, "energyScale" .= energyTop, "rateScale" .= rateTop, "endpoints" .= [r | (_, _, _, r) <- endpoints], "comparisons" .= reports]
  BL.writeFile (output </> "checks.json") (encode report)
  template <- TIO.readFile "study/fold-material/matched-energy.html"
  TIO.writeFile (destination </> "matched-energy.html") (T.replace "/*MATCHED_ENERGY*/null" (TE.decodeUtf8 (BL.toStrict (encode report))) template)
  putStrLn "Wrote matched-energy.html from four saved endpoints; both rule archives agree. No optimizer or repair ran."

groupReport :: Text -> [EdgeChange] -> Value
groupReport name cs =
  object
    [ "name" .= name,
      "before" .= a,
      "after" .= b,
      "delta" .= (b - a),
      "percent" .= (if a == 0 then Nothing else Just (100 * (b - a) / a)),
      "sharedCount" .= length shared,
      "addedCount" .= length added,
      "removedCount" .= length removed,
      "sharedDelta" .= sum (map edgeDelta shared),
      "coefficientPart" .= sum (map coefficientPart shared),
      "anglePart" .= sum (map anglePart shared),
      "addedEnergy" .= sum (map edgeDelta added),
      "removedEnergy" .= sum (map edgeDelta removed),
      "accountingResidual" .= (sum (map edgeDelta cs) - (b - a))
    ]
  where
    a = sum (map (bendEnergy . oldBend) cs)
    b = sum (map (bendEnergy . newBend) cs)
    shared = filter (\c -> isJust (oldBend c) && isJust (newBend c)) cs
    added = filter (isNothing . oldBend) cs
    removed = filter (isNothing . newBend) cs

changeJson :: EdgeChange -> Value
changeJson c =
  object
    [ "location" .= rowJson (changeLocation c),
      "before" .= fmap rowJson (oldBend c),
      "after" .= fmap rowJson (newBend c),
      "membership" .= (if isNothing (oldBend c) then "Added" else if isNothing (newBend c) then "Removed" else "Shared" :: Text),
      "direction" .= edgeDirection (changeLocation c),
      "delta" .= edgeDelta c,
      "coefficientPart" .= coefficientPart c,
      "anglePart" .= anglePart c
    ]

differenceMap :: Double -> [EdgeChange] -> Text
differenceMap top changes = renderSvg defaultPage {pageWidth = 720, pageHeight = 260, pageMargin = 25, pageBackground = Nothing, pageTitle = Just "Signed passive-energy contributions on the material panel"} $ diagramWithExtent (Box (V2 (-0.025) (-0.03)) (V2 0.53 0.18)) shapes
  where
    place (V2 u v) = V2 (abs u) (0.12 * (v + 0.5))
    colour d | abs d < top / 100 = "#cbc4b7" | d > 0 = "#a64732" | otherwise = "#287b87"
    shapes =
      [Fill (Colour "#f3ede1") [[V2 0 0, V2 0.5 0, V2 0.5 0.12, V2 0 0.12]]]
        ++ [Polyline (solid (Colour (colour (edgeDelta c))) (0.7 + 4 * abs (edgeDelta c) / top)) [place (locatedFrom h), place (locatedTo h)] | c <- changes, let h = changeLocation c]
        ++ [Polyline (solid (Colour "#777163") 0.6) [V2 x (-0.006), V2 x 0.132] | x <- [1 / 8, 7 / 16]]
        ++ [Label (Colour "#55534d") 11 (V2 x (-0.023)) label | (x, label) <- [(0, "crease"), (0.125, "1/8 · held edge"), (0.4375, "7/16"), (0.5, "1/2")]]
        ++ [Label (Colour "#55534d") 11 (V2 0 0.16) ("Line width: |energy change|; maximum " <> num top)]

field :: Text -> Value -> IO Value
field key = either die pure . parseEither (withObject "saved field" (.: Key.fromText key))

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
