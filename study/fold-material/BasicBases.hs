-- | Six traditional bases as closed, zero-thickness sheets. A base is a
-- reusable folded starting shape; squash and petal folds open and reshape
-- flaps (see docs/glossary.md). These constructions belong to the study:
-- they supply regression inputs, not a general instruction interpreter.
--
-- Coordinates come from halves, quarters and angle bisectors of a unit
-- square. We describe material creases, then use the production crossing
-- cutter and face tracer. In particular, frog's petal hinges cross its old
-- midlines: leaving those intersections unsplit would test a different graph.
-- Assignments describe the final state, not every preparatory crease.
--
-- Mountain and valley make the same rigid motion at 180 degrees, but put
-- different faces on top. Folding alone therefore cannot verify these bases;
-- BasicBaseSpec also checks stacking, contact and visible regions. The
-- coordinate derivation and construction references are in
-- docs/notes/six-more-base-endpoints.md. No intermediate motion is prescribed.
module BasicBases (Base (..), basicBases, baseFrame, baseFile, frogMilestones) where

import Data.List (nub)
import Data.Text (Text)
import Senbazuru.Fold.Crossings (withPlanarFaces)
import Senbazuru.Fold.Query (FoldError)
import Senbazuru.Fold.Types
import Senbazuru.Geometry (V2 (..))

data Base = Base
  { baseId :: String,
    baseTitle :: Text,
    baseDescription :: Text,
    baseCreases :: [(V2, V2, Assignment)]
  }

basicBases :: [Base]
basicBases =
  [ Base "helmet" "Helmet base" "Fold diagonally, then bring both corners of the doubled triangle to its tip. The reverse view reveals the two flaps." helmet,
    Base "organ" "Organ base" "Fold a book, then open and squash its two side flaps into a roof above four rectangular panels." organ,
    Base "frog" "Frog base" "Squash four flaps of a square base, then lift four petals. Four long tips meet at one end; the original sheet centre makes the shorter tip at the other." frog,
    Base "boat" "Boat base" "Open both ends of a cupboard fold into two boat-shaped pockets. This is the flat double-boat base, before opening a finished boat." boat,
    Base "pig" "Pig base" "Squash all four corners of a cupboard fold. Its outline matches the boat base, but its four triangular flaps meet at the centre." pig,
    Base "diamond" "Diamond base" "Fold a kite, then fold its opposite two edges to the same diagonal through both layers. The crease direction reverses on the turned-over layer." diamond
  ]

-- | Intern segment endpoints once, then cut every crossing and trace faces.
-- The lookup is total: the table is made from exactly these segment endpoints.
baseFrame :: Base -> Either FoldError Frame
baseFrame base = withPlanarFaces sheet
  where
    segments = [(V2 0 0, V2 1 0, Border), (V2 1 0, V2 1 1, Border), (V2 1 1, V2 0 1, Border), (V2 0 1, V2 0 0, Border)] ++ baseCreases base
    points = nub [p | (a, b, _) <- segments, p <- [a, b]]
    ids = zip points (map VertexId [0 ..])
    edges = [(i, j, kind) | (a, b, kind) <- segments, Just i <- [lookup a ids], Just j <- [lookup b ids]]
    angle Mountain = -180
    angle Valley = 180
    angle _ = 0
    sheet =
      emptyFrame
        { frameTitle = Just (baseTitle base),
          frameDescription = Just (baseDescription base),
          frameClasses = ["creasePattern"],
          frameAttributes = ["2D"],
          frameUnit = Just "unit",
          verticesCoords = [[x, y] | V2 x y <- points],
          edgesVertices = [(a, b) | (a, b, _) <- edges],
          edgesAssignment = [kind | (_, _, kind) <- edges],
          edgesFoldAngle = [angle kind | (_, _, kind) <- edges]
        }

baseFile :: Base -> Frame -> FoldFile
baseFile base sheet =
  FoldFile
    { fileSpec = Just 1.2,
      fileCreator = Just "senbazuru (constructed here; see study/fold-material/BasicBases.hs)",
      fileAuthor = Nothing,
      fileTitle = Just (baseTitle base),
      fileDescription = Nothing,
      fileClasses = [],
      keyFrame = sheet,
      otherFrames = []
    }

helmet, organ, frog, boat, pig, diamond :: [(V2, V2, Assignment)]
helmet =
  [ (V2 0 0, V2 1 1, Valley),
    (V2 0.5 0, V2 0.5 0.5, Valley),
    (V2 0.5 0.5, V2 0.5 1, Mountain),
    (V2 0 0.5, V2 0.5 0.5, Mountain),
    (V2 0.5 0.5, V2 1 0.5, Valley)
  ]
organ =
  (V2 0.25 0.5, V2 0.75 0.5, Valley)
    : concat
      [ [(V2 c 0.5, V2 c 1, Mountain), (V2 side 0.25, V2 c 0.5, Valley), (V2 side 0.75, V2 c 0.5, Valley)]
        | (c, side) <- [(0.25, 0), (0.75, 1)]
      ]
boat =
  [ (V2 0.25 0.25, V2 0.25 0.75, Valley),
    (V2 0.75 0.25, V2 0.75 0.75, Valley),
    (V2 0.25 0.25, V2 0.75 0.25, Valley),
    (V2 0.25 0.75, V2 0.75 0.75, Valley)
  ]
    ++ concat
      [ [(V2 x y, V2 bx by, Valley), (V2 x y, V2 0.5 by, Mountain)]
        | (x, bx) <- [(0.25, 0), (0.75, 1)],
          (y, by) <- [(0.25, 0), (0.75, 1)]
      ]
pig =
  [ (V2 0.25 0.25, V2 0.75 0.25, Valley),
    (V2 0.25 0.75, V2 0.75 0.75, Valley)
  ]
    ++ concat
      [ [(V2 x y, V2 bx by, Valley), (V2 x y, V2 bx 0.5, Valley), (V2 x y, V2 x by, Mountain)]
        | (x, bx) <- [(0.25, 0), (0.75, 1)],
          (y, by) <- [(0.25, 0), (0.75, 1)]
      ]
diamond =
  let d = 1 / sqrt 2
      a = V2 d (1 - d)
      b = V2 (1 - d) d
      h = sqrt 2 - 1
      k = h * h
   in [ (V2 0 0, V2 1 h, Valley),
        (V2 0 0, V2 h 1, Valley),
        (V2 1 k, a, Mountain),
        (V2 1 1, a, Valley),
        (V2 1 1, b, Valley),
        (V2 k 1, b, Mountain)
      ]
frog = frogCreases False 4 4

-- | Flat checkpoints for a human folding guide, not samples of a continuous
-- motion. A squash bisects one sector about the sheet centre. Its two new
-- creases reach the boundary at 1-d and d; a later petal fold replaces their
-- outer parts with the branches meeting at the petal's shoulders.
frogMilestones :: [(String, Base)]
frogMilestones =
  [ milestone "square" "Square base" 0 0,
    milestone "one-squash" "One squash fold" 1 0,
    milestone "four-squashes" "Four squash folds" 4 0,
    milestone "one-petal" "One petal fold" 4 1,
    milestone "complete" "Frog base" 4 4
  ]
  where
    milestone key title squashes petals =
      (key, Base ("frog-guide-" ++ key) title "Flat milestone of the frog folding guide; no motion is implied between checkpoints." (frogCreases (squashes == 4) squashes petals))

frogCreases :: Bool -> Int -> Int -> [(V2, V2, Assignment)]
frogCreases openPages squashes petals =
  concat
    [ [(rotate n start, rotate n end, kind) | (start, end, kind) <- sector n]
      | n <- [0 .. 3]
    ]
  where
    d = 1 / sqrt 2
    r = (1 - d) / 2
    c = V2 0.5 0.5
    a = V2 (0.5 - r) r
    b = V2 (0.5 + r) r
    t = V2 0.5 r
    s = V2 0.5 0
    -- Two opposite diagonals stay flat, as in the square base. Squashing
    -- reverses each inner midline; lifting the petal reverses its outer part.
    -- Opening two opposite faces like book pages moves the flat guides from
    -- the old diagonals to those faces' midlines. This exposes the short edge
    -- and lifted petal in the guide, without changing the loose-corner tips.
    opened n = openPages && even n
    sector n = (c, V2 0 0, if openPages || even n then Mountain else Flat) : flap n
    flap n
      | n < petals =
          [ (c, t, if opened n then Flat else Mountain),
            (t, s, if opened n then Flat else Valley),
            (c, a, Valley),
            (c, b, Valley),
            (V2 0 0, a, Valley),
            (V2 1 0, b, Valley),
            (s, a, Valley),
            (s, b, Valley),
            (a, b, Mountain)
          ]
      | n < squashes = [(c, s, if opened n then Flat else Mountain), (c, V2 (1 - d) 0, Valley), (c, V2 d 0, Valley)]
      | otherwise = [(c, s, Valley)]
    rotate :: Int -> V2 -> V2
    rotate 0 p = p
    rotate n (V2 x y) = rotate (n - 1) (V2 (1 - y) x)
