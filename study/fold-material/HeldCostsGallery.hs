-- | Saved held-panel endpoints, remeasured without solving or repairing.
-- Material-edge matching comes from MatchedEnergy; HeldCosts fixes the bins
-- and checks the original solver policy. A shared plotting scale keeps small
-- contributions small when switching meshes or panels. SVG geometry belongs
-- here in Diagram, while the HTML only selects plots and formats measurements.
module HeldCostsGallery (writeHeldCosts, differenceMap, heldChangeJson, costMap, plot) where

import BendLocations
import BendLocationsGallery (plotPoint)
import ClosedCrease
import Control.Monad (forM, unless, when)
import CoupledCrease
import Data.Aeson (Value (..), eitherDecode, encode, object, withObject, (.:), (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KM
import Data.Aeson.Types (parseEither)
import Data.ByteString.Lazy qualified as BL
import Data.List (isPrefixOf)
import Data.Map.Strict qualified as M
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending
import HeldCosts
import HeldEquilibrium
import HeldEquilibriumGallery (HeldState (..), measureHeldState, writeMeasuredHeldState)
import MatchedEnergy
import MatchedEnergyGallery (changeJson, groupReport)
import OuterContinuation (agreeMeasurements)
import PrescribedBend
import Senbazuru.Diagram
import Senbazuru.Explain (Explain (..), num)
import Senbazuru.Fold.Types (FoldFile (..))
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Render.Svg
import System.Directory (canonicalizePath, createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath (splitDirectories, (</>))

writeHeldCosts :: FilePath -> FilePath -> IO ()
writeHeldCosts source destination = do
  let output = destination </> "held-costs"
  sourcePath <- splitDirectories <$> canonicalizePath source
  outputPath <- splitDirectories <$> canonicalizePath output
  when (sourcePath `isPrefixOf` outputPath || outputPath `isPrefixOf` sourcePath) (die "held-costs output and source directories must not overlap")
  bytes <- BL.readFile (source </> "checks.json")
  document <- either die pure (eitherDecode bytes)
  inputs <- forM heldCases $ \(key, layout, budget) -> do
    c <- checked (heldCase layout budget)
    record <- checked (heldRecord (T.pack key) layout c document)
    single <- BL.readFile (source </> key <> "-checks.json") >>= either die pure . eitherDecode
    checked (agreeMeasurements record single)
    raw <- BL.readFile (source </> key <> "-after.fold")
    file <- either die pure (eitherDecode raw)
    mesh <- checked (savedBendMesh (heldFixture c) (keyFrame file))
    measured <- measureHeldState (heldFixture c) mesh
    original <- field "states" record >>= field "after"
    checked (agreeMeasurements original (heldStateReport measured))
    unless (heldStateValid measured) (die "saved held-panel endpoint failed fresh geometry checks")
    pure (key, c, raw, mesh, measured)
  createDirectoryIfMissing True output
  BL.writeFile (output </> "source-checks.json") bytes
  endpoints <- forM inputs $ \(key, c, raw, mesh, measured) -> do
    let fixture = heldFixture c
    (report, _, _, _, _) <- writeMeasuredHeldState output fixture key (T.pack key <> " · unchanged saved endpoint") mesh measured
    -- The exporter above is useful for inspection, but the FOLD itself stays
    -- byte-for-byte identical, including its original caption and metadata.
    BL.writeFile (output </> key <> ".fold") raw
    rows <- checked (locateBends (coupledReference fixture) {closedMesh = mesh})
    pure (key, rows, object ["id" .= key, "label" .= key, "sourceConverged" .= True, "sourcePassed" .= True, "state" .= report])
  let get key = case [rs | (k, rs, _) <- endpoints, k == key] of [rs] -> pure rs; _ -> die "missing unique held endpoint"
      passive upper = filter (\h -> measuredUpper (locatedMeasure h) == upper && hingeRole (measuredHinge (locatedMeasure h)) == PanelBend)
  pairs <- forM [(ka, kb, upper, panel) | (ka, kb) <- heldPairs, (upper, panel) <- [(False, "lower" :: Text), (True, "upper")]] $ \(ka, kb, upper, panel) -> do
    a <- passive upper <$> get ka
    b <- passive upper <$> get kb
    cs <- checked (compareBends a b)
    pure (ka, kb, panel, a, b, cs)
  let allRows = concat [a ++ b | (_, _, _, a, b, _) <- pairs]
      edgeTop = maximum (1e-12 : [abs (edgeDelta c) | (_, _, _, _, _, cs) <- pairs, c <- cs])
      siteTop = maximum (1e-12 : [abs d | (_, _, _, _, _, cs) <- pairs, (_, d) <- sites cs])
      energyTop = maximum (1e-12 : [sum (map (measuredEnergy . locatedMeasure) rs) | (_, _, _, a, b, _) <- pairs, rs <- [a, b]])
      angleTop = maximum (1e-12 : [abs (measuredAngle (locatedMeasure h)) | h <- allRows, edgeDirection h == "Transverse"])
      rateTop = maximum (1e-12 : [abs r | h <- allRows, Just r <- [locatedRate h]])
  reports <- forM pairs $ \(ka, kb, panel, a, b, cs) -> do
    let stem = ka <> "-" <> kb <> "-" <> T.unpack panel
        write suffix = TIO.writeFile (output </> stem <> "-" <> suffix <> ".svg")
        rangePlot title top profile = plot title top True [(colour, [V2 x mean | (x, mean, _, _) <- profile rs]) | (colour, rs) <- [("#a67832", a), ("#306575", b)]] [Polyline (solid (Colour colour) 0.7) [plotPoint top x lo, plotPoint top x hi] | (colour, rs) <- [("#a67832", a), ("#306575", b)], (x, _, lo, hi) <- profile rs]
    write "map" (differenceMap edgeTop cs)
    write "sites" (plot "Cost change at each material distance" siteTop True [] [Polyline (solid (Colour (signedColour d)) 2) [plotPoint siteTop x 0, plotPoint siteTop x d] | (x, d) <- sites cs])
    write "cumulative" (plot "Cumulative passive cost" energyTop False [("#a67832", cumulativeEnergy a), ("#306575", cumulativeEnergy b)] [])
    write "angles" (rangePlot "Transverse turn (radians)" angleTop transverseAngles)
    write "rates" (rangePlot "Turn / neighboring material spacing" rateTop transverseRates)
    let report =
          object
            [ "id" .= stem,
              "before" .= ka,
              "after" .= kb,
              "panel" .= panel,
              "totals" .= groupReport "all" cs,
              "regions" .= [groupReport (T.pack (show r)) [c | c <- cs, heldRegion (locatedDistance (changeLocation c)) == r] | r <- [minBound .. maxBound]],
              "directions" .= [groupReport d [c | c <- cs, edgeDirection (changeLocation c) == d] | d <- ["Transverse", "Lengthwise", "Diagonal"]],
              "sites" .= [object ["distance" .= x, "delta" .= d] | (x, d) <- sites cs],
              "profiles" .= object ["before" .= profiles a, "after" .= profiles b],
              "edges" .= map heldChangeJson cs
            ]
    BL.writeFile (output </> stem <> "-checks.json") (encode report)
    pure report
  let report = object ["gallery" .= ("held-costs" :: Text), "solverRun" .= False, "coordinatesChanged" .= False, "edgeDeltaScale" .= edgeTop, "siteDeltaScale" .= siteTop, "energyScale" .= energyTop, "angleScale" .= angleTop, "rateScale" .= rateTop, "endpoints" .= [r | (_, _, r) <- endpoints], "comparisons" .= reports]
  BL.writeFile (output </> "checks.json") (encode report)
  template <- TIO.readFile "study/fold-material/held-costs.html"
  TIO.writeFile (destination </> "held-costs.html") (T.replace "/*HELD_COSTS*/null" (TE.decodeUtf8 (BL.toStrict (encode report))) template)
  putStrLn "Wrote held-costs.html: four saved endpoints, eight panel comparisons. No solve or repair ran."

sites :: [EdgeChange] -> [(Double, Double)]
sites = M.toAscList . M.fromListWith (+) . map (\c -> (locatedDistance (changeLocation c), edgeDelta c))

profiles :: [LocatedBend] -> Value
profiles rows = object ["angles" .= map entry (transverseAngles rows), "rates" .= map entry (transverseRates rows)]
  where
    entry (x, mean, lo, hi) = object ["distance" .= x, "mean" .= mean, "min" .= lo, "max" .= hi]

-- | The copied source measurements keep their historical bin names. New
-- comparisons use only the fixed/free bins; no bending band is imposed here.
heldChangeJson :: EdgeChange -> Value
heldChangeJson c = case changeJson c of
  Object o -> Object (KM.mapWithKey (\k v -> if k `elem` ["location", "before", "after"] then region v else v) o)
  v -> v
  where
    region (Object o) = Object (KM.insert "region" (String (T.pack (show (heldRegion (locatedDistance (changeLocation c)))))) o)
    region v = v

signedColour :: Double -> Text
signedColour d = if d >= 0 then "#a64732" else "#287b87"

plot :: Text -> Double -> Bool -> [(Text, [V2])] -> [Shape] -> Text
plot title top signed traces extra = renderSvg defaultPage {pageWidth = 720, pageHeight = 300, pageMargin = 25, pageBackground = Nothing, pageTitle = Just title} $ diagramWithExtent (Box (V2 (-0.025) (if signed then -0.19 else -0.04)) (V2 0.53 0.20)) shapes
  where
    shapes =
      [Polyline (solid (Colour "#aaa294") 0.8) [V2 0 0, V2 0.5 0]]
        ++ [Polyline (solid (Colour "#d9d1c3") 0.6) [V2 x (if signed then -0.15 else 0), V2 x 0.15] | x <- [1 / 8, 5 / 32]]
        ++ [Label (Colour "#55534d") 11 (V2 0 0.18) (title <> " · top " <> num top)]
        ++ [Polyline (solid (Colour colour) 1.6) [plotPoint top x y | V2 x y <- points] | (colour, points) <- reverse traces]
        ++ extra
        ++ [Label (Colour "#55534d") 11 (V2 x (if signed then -0.18 else -0.027)) label | (x, label) <- [(0, "crease · 0"), (0.125, "1/8"), (0.25, "1/4"), (0.5, "1/2")]]

differenceMap :: Double -> [EdgeChange] -> Text
differenceMap top cs = costMap top [(locatedFrom (changeLocation c), locatedTo (changeLocation c), edgeDelta c) | c <- cs]

-- | A shared map for passive-spring and numerical length-edge costs.
costMap :: Double -> [(V2, V2, Double)] -> Text
costMap top edges = renderSvg defaultPage {pageWidth = 720, pageHeight = 260, pageMargin = 25, pageBackground = Nothing, pageTitle = Just "Signed cost changes on unfolded material"} $ diagramWithExtent (Box (V2 (-0.025) (-0.03)) (V2 0.53 0.18)) shapes
  where
    place (V2 u v) = V2 (abs u) (0.12 * (v + 0.5))
    shapes =
      [Fill (Colour "#f3ede1") [[V2 0 0, V2 0.5 0, V2 0.5 0.12, V2 0 0.12]], Fill (Colour "#e8e1d3") [[V2 0 0, V2 0.125 0, V2 0.125 0.12, V2 0 0.12]]]
        ++ [Polyline (solid (Colour (if abs d < top / 100 then "#cbc4b7" else signedColour d)) (0.7 + 4 * abs d / top)) [place a, place b] | (a, b, d) <- edges]
        ++ [Polyline (solid (Colour "#777163") 0.6) [V2 x (-0.006), V2 x 0.132] | x <- [1 / 8, 5 / 32]]
        ++ [Label (Colour "#55534d") 11 (V2 x (-0.023)) label | (x, label) <- [(0, "crease"), (0.125, "held edge"), (0.5, "1/2")]]
        ++ [Label (Colour "#55534d") 11 (V2 0 0.16) ("Width: |cost change|; maximum " <> num top)]

field :: Text -> Value -> IO Value
field key = either die pure . parseEither (withObject "saved field" (.: Key.fromText key))

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure
