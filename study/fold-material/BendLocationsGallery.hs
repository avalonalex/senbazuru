-- | Re-read the saved fixed-width study without calling its solver. Retain
-- the source report, copy FOLDs byte-for-byte, and bind their historical
-- convergence to fresh material/contact checks before making a comparison.
-- All maps and plots are made through Diagram in Haskell; the page only
-- selects assets and presents measured tables. See BendLocations for the
-- distinction between a spring location and a physical energy density.
module BendLocationsGallery (writeBendLocations) where

import BandBoundary
import BendLocations
import ClosedCrease
import Control.Monad (forM, forM_, unless)
import CoupledCrease
import CoupledCreaseGallery (measure)
import Data.Aeson (Value, eitherDecode, encode, object, withObject, (.:), (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.Types (Parser, parseEither)
import Data.ByteString.Lazy qualified as BL
import Data.List (find)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import FoldBending
import PrescribedBend
import Senbazuru.Diagram
import Senbazuru.Explain (Explain (..), num, tshow)
import Senbazuru.Fold.Load (loadFoldFile)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (Box (..), V2 (..))
import Senbazuru.Geometry.VectorSpace
import Senbazuru.Render.Svg
import System.Directory (copyFile, createDirectoryIfMissing)
import System.Exit (die)
import System.FilePath ((</>))
import UnequalCrease

data Endpoint = Endpoint
  { endpointId :: Text,
    endpointControl :: Text,
    endpointRule :: Text,
    endpointLength :: Int,
    endpointRows :: [LocatedBend],
    endpointReport :: Value
  }

writeBendLocations :: FilePath -> FilePath -> IO ()
writeBendLocations source destination = do
  report <- BL.readFile (source </> "checks.json") >>= either die pure . eitherDecode
  runs <- parsed (withObject "boundary-length report" readRuns) report
  let output = destination </> "bend-locations"
  createDirectoryIfMissing True output
  endpoints <- forM [(n, r, c) | n <- [2, 4], r <- ["original", "fractional"], c <- ["matched", "band", "band-off"]] $ \(n, rule, control) -> loadEndpoint source output runs n rule control
  copyFile (source </> "checks.json") (output </> "source-checks.json")
  let maxima role = maximum (1e-12 : [density h | e <- endpoints, h <- endpointRows e, hingeRole (measuredHinge (locatedMeasure h)) == role])
  forM_ endpoints $ \e -> forM_ [(False, "lower"), (True, "upper")] $ \(upper, panel) -> forM_ [(PanelBend, "passive"), (BendControl, "imposed")] $ \(role, kind) -> do
    let selected = selectRows upper role e
        stem = endpointId e <> "-" <> panel <> "-" <> kind
    TIO.writeFile (output </> T.unpack stem <> ".svg") (mapSvg (maxima role) selected)
  pairs <- forM [(c, r, upper, panel) | c <- ["matched", "band", "band-off"], r <- ["original", "fractional"], (upper, panel) <- [(False, "lower"), (True, "upper")]] $ \(control, rule, upper, panel) -> do
    let get kind n = maybe (die "missing saved comparison") pure (find (\e -> endpointControl e == kind && endpointRule e == rule && endpointLength e == n) endpoints)
    a <- get control 2
    b <- get control 4
    ma <- get "matched" 2
    mb <- get "matched" 4
    let stem = control <> "-" <> rule <> "-" <> panel
        passive = selectRows upper PanelBend
        traces = [("#a14e35", a), ("#236e75", b)] ++ if control == "matched" then [] else [("#baaa9a", ma), ("#789496", mb)]
        rates e = transverseRates (passive e)
        maxRate = maximum (1e-12 : [abs v | (_, e) <- traces, (_, mean, lo, hi) <- rates e, v <- [mean, lo, hi]])
    TIO.writeFile (output </> T.unpack stem <> "-turns.svg") (plotSvg "Signed turn / material spacing" maxRate True [(colour, [V2 x mean | (x, mean, _, _) <- rates e]) | (colour, e) <- traces] [Polyline (solid (Colour colour) 0.7) [plotPoint maxRate x lo, plotPoint maxRate x hi] | (colour, e) <- take 2 traces, (x, _, lo, hi) <- rates e])
    forM_ [(PanelBend, "passive"), (BendControl, "imposed")] $ \(role, kind) -> do
      let values = [(colour, cumulativeEnergy (selectRows upper role e)) | (colour, e) <- traces]
          top = maximum (1e-12 : [y | (_, points) <- values, V2 _ y <- points])
      TIO.writeFile (output </> T.unpack stem <> "-" <> kind <> "-cumulative.svg") (plotSvg "Cumulative spring energy" top False values [])
    pure (object ["id" .= stem, "coarse" .= endpointId a, "fine" .= endpointId b, "matchedCoarse" .= endpointId ma, "matchedFine" .= endpointId mb])
  let document = object ["solverRun" .= False, "coordinatesChanged" .= False, "passiveMapMaximum" .= maxima PanelBend, "imposedMapMaximum" .= maxima BendControl, "endpoints" .= map endpointReport endpoints, "pairs" .= pairs]
  BL.writeFile (output </> "checks.json") (encode document)
  template <- TIO.readFile "study/fold-material/bend-locations.html"
  TIO.writeFile (destination </> "bend-locations.html") (T.replace "/*BEND_LOCATIONS*/null" (TE.decodeUtf8 (BL.toStrict (encode document))) template)
  putStrLn "Wrote bend-locations.html from twelve saved endpoints; no optimizer or repair was run."
  where
    readRuns o = do
      name <- o .: "gallery"
      unless (name == ("boundary-length" :: Text)) (fail "expected saved boundary-length output")
      o .: "runs"

loadEndpoint :: FilePath -> FilePath -> [Value] -> Int -> Text -> Text -> IO Endpoint
loadEndpoint source output runs n rule control = do
  let stem = control <> "-" <> tshow n <> "-" <> rule
      filename = T.unpack stem <> "-after.fold"
      getId = parseEither (withObject "run" (.: "id"))
  record <- case [r | r <- runs, getId r == Right stem] of
    [r] -> pure r
    _ -> die ("expected exactly one saved run for " <> T.unpack stem)
  (passed, converged, oldMeasurements, oldBending) <-
    parsed
      ( withObject
          "run"
          ( \o -> do
              size <- o .: "subdivision"
              width <- o .: "widthSubdivision"
              boundary <- o .: "boundaryRule"
              kind <- o .: "control"
              unless (size == n && width == (1 :: Int) && kind == control && boundary == (if rule == "original" then "OriginalTurns" else "FractionalTurns" :: Text)) (fail "saved run identity disagrees with selected fixture")
              passed <- o .: "passed"
              solve <- o .: "solve"
              converged <- solve .: "converged"
              measurements <- o .: "measurements"
              after <- measurements .: "after"
              bending <- o .: "bending"
              costs <- bending .: "after"
              pure (passed, converged, after, costs)
          )
      )
      record
  fixture <- checked (bandBoundaryFixture (if rule == "original" then OriginalTurns else FractionalTurns) n 1 (case control of "matched" -> MatchedHolds; "band" -> UpperBand; _ -> BandWithoutContact))
  fr <- keyFrame <$> (loadFoldFile (source </> filename) >>= checked)
  mesh <- checked (savedBendMesh fixture fr)
  (measurement, valid) <- measure fixture mesh
  rows <- checked (locateBends (coupledReference fixture) {closedMesh = mesh})
  forM_ ["maxRelativeEdgeError", "maxCreaseErrorRadians", "panelBendingEnergy", "heldPositionError", "creaseEnergy"] $ \key -> do
    x <- field key oldMeasurements
    y <- field key measurement
    agree key x y
  let total upper role = sum [measuredEnergy (locatedMeasure h) | h <- rows, measuredUpper (locatedMeasure h) == upper, hingeRole (measuredHinge (locatedMeasure h)) == role]
      expectedCosts = [("lowerPassiveEnergy", total False PanelBend), ("upperPassiveEnergy", total True PanelBend), ("imposedEnergy", total True BendControl)]
  forM_ expectedCosts $ \(key, value) -> field key oldBending >>= agree key value
  copyFile (source </> filename) (output </> filename)
  let eligibility = control /= "band-off" && passed && converged && valid
      report =
        object
          [ "id" .= stem,
            "control" .= control,
            "rule" .= rule,
            "length" .= n,
            "sourcePassed" .= (passed :: Bool),
            "sourceConverged" .= (converged :: Bool),
            "geometryPassed" .= valid,
            "eligible" .= eligibility,
            "measurements" .= measurement,
            "sourceBending" .= oldBending,
            "rows" .= map rowJson rows,
            "regions" .= regionJson rows,
            "fold" .= filename
          ]
  pure (Endpoint stem control rule n rows report)
  where
    field key = parsed (withObject "measurement" (.: Key.fromText key))
    agree key x y = unless (not (isNaN x || isInfinite x || isNaN y || isInfinite y) && abs (x - y :: Double) <= 1e-12 * max 1 (abs x)) (die ("saved report disagrees with measured " <> T.unpack key))

selectRows :: Bool -> HingeRole -> Endpoint -> [LocatedBend]
selectRows upper role e = [h | h <- endpointRows e, measuredUpper (locatedMeasure h) == upper, hingeRole (measuredHinge (locatedMeasure h)) == role]

regionJson :: [LocatedBend] -> [Value]
regionJson rows =
  [ object
      [ "panel" .= panel,
        "kind" .= kind,
        "values" .= [object ["region" .= show r, "energy" .= e] | (r, e) <- regionEnergy selected]
      ]
    | (upper, panel) <- [(False, "lower" :: Text), (True, "upper")],
      (role, kind) <- [(PanelBend, "passive" :: Text), (BendControl, "imposed")],
      let selected = [h | h <- rows, measuredUpper (locatedMeasure h) == upper, hingeRole (measuredHinge (locatedMeasure h)) == role]
  ]

density :: LocatedBend -> Double
density h = measuredEnergy (locatedMeasure h) / norm (locatedTo h ^-^ locatedFrom h)

rowJson :: LocatedBend -> Value
rowJson h =
  object
    [ "vertices" .= [a, b, c, d],
      "from" .= point (locatedFrom h),
      "to" .= point (locatedTo h),
      "distance" .= locatedDistance h,
      "region" .= show (locatedRegion h),
      "panel" .= (if measuredUpper m then "upper" else "lower" :: Text),
      "role" .= show (hingeRole spring),
      "angle" .= measuredAngle m,
      "target" .= hingeRest spring,
      "stiffness" .= hingeStiffness spring,
      "energy" .= measuredEnergy m,
      "energyPerEdgeLength" .= density h,
      "transverseRate" .= locatedRate h
    ]
  where
    m = locatedMeasure h
    spring = measuredHinge m
    (a, b, c, d) = hingeVertices spring
    point (V2 x y) = [x, y]

mapSvg :: Double -> [LocatedBend] -> Text
mapSvg top rows = renderSvg defaultPage {pageWidth = 650, pageHeight = 230, pageMargin = 25, pageBackground = Nothing, pageTitle = Just "Spring costs on the unfolded panel"} $ diagramWithExtent (Box (V2 (-0.03) (-0.01)) (V2 0.53 0.17)) shapes
  where
    -- Width is compressed equally in every map; it is stated on the page.
    place (V2 u v) = V2 (abs u) (0.12 * (v + 0.5))
    palette = ["#ddd5c7", "#d9b975", "#b67a36", "#a34035", "#572b3a"]
    colour x = fromMaybe "#572b3a" (lookup (min 4 (floor (5 * x / top) :: Int)) (zip [0 ..] palette))
    shapes =
      [Fill (Colour "#f3ede1") [[V2 0 0, V2 0.5 0, V2 0.5 0.12, V2 0 0.12]]]
        ++ [Polyline (solid (Colour (colour (density h))) 2.2) [place (locatedFrom h), place (locatedTo h)] | h <- rows]
        ++ [Polyline (solid (Colour "#274e58") 0.8) [V2 x (-0.008), V2 x 0.135] | x <- [0.125, 0.4375]]
        ++ [Label (Colour "#55534d") 11 (V2 x 0.15) label | (x, label) <- [(0, "crease"), (0.125, "held / band start"), (0.4375, "band end")]]

plotPoint :: Double -> Double -> Double -> V2
plotPoint scale x y = V2 x (0.15 * y / scale)

plotSvg :: Text -> Double -> Bool -> [(Text, [V2])] -> [Shape] -> Text
plotSvg title top signed traces extra = renderSvg defaultPage {pageWidth = 720, pageHeight = 300, pageMargin = 25, pageBackground = Nothing, pageTitle = Just title} $ diagramWithExtent (Box (V2 (-0.025) (if signed then -0.19 else -0.04)) (V2 0.53 0.20)) shapes
  where
    shapes =
      [Polyline (solid (Colour "#aaa294") 0.8) [V2 0 0, V2 0.5 0]]
        ++ [Polyline (solid (Colour "#ccc3b4") 0.8) [V2 x (if signed then -0.15 else 0), V2 x 0.15] | x <- [0.125, 0.4375]]
        ++ [Label (Colour "#55534d") 11 (V2 0 0.18) (title <> " · top " <> num top)]
        ++ [Polyline (solid (Colour colour) 1.6) [plotPoint top x y | V2 x y <- points] | (colour, points) <- reverse traces]
        ++ extra
        ++ [Label (Colour "#55534d") 11 (V2 x (if signed then -0.18 else -0.027)) label | (x, label) <- [(0, "0"), (0.125, "1/8"), (0.4375, "7/16"), (0.5, "1/2")]]

checked :: (Explain e) => Either e a -> IO a
checked = either (die . T.unpack . explain) pure

parsed :: (Value -> Parser a) -> Value -> IO a
parsed parser = either die pure . parseEither parser
