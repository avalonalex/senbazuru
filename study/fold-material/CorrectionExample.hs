-- | A connected square whose numerical shortcut passes through itself.
-- The two endpoint poses are a 120-degree fold to opposite sides of the same
-- diagonal. Both preserve every material edge length. Moving the lifted corner
-- straight between them passes through the base triangle; it is not the safe
-- physical route of unfolding and folding again. The gallery and tests share
-- this small counterexample to endpoint-only acceptance.
module CorrectionExample (crossingCorrection, openingStrip) where

import FoldBending (Hinge (..), HingeRole (..))
import SelfContactExample (CurlError, CurledPanel (..), curledPanelAt)
import Senbazuru.Geometry (V2 (..))
import Senbazuru.Geometry.V3 (V3 (..))
import Senbazuru.Origami.Surface (MaterialMesh, Mesh (..), Sample (..))

crossingCorrection :: (MaterialMesh, MaterialMesh)
crossingCorrection = (pose 1, pose (-1))
  where
    pose side =
      Mesh
        [ Sample (V2 0 0) (V3 0 0 0),
          Sample (V2 1 0) (V3 1 0 0),
          Sample (V2 0 1) (V3 0 1 0),
          Sample (V2 1 1) (V3 0.25 0.25 (side * sqrt (3 / 8)))
        ]
        [(0, 1, 2), (1, 3, 2)]

-- | A small opening, using the same strip as the contact-history regression.
-- Controls prefer 27 degrees instead of 30, while passive springs prefer zero;
-- their 4:1 stiffness balance prefers 21.6 degrees and opens the 22.25-degree curl.
openingStrip :: Either CurlError CurledPanel
openingStrip = do
  fixture <- curledPanelAt 16 22.25
  let open hinge = if hingeRole hinge == BendControl then hinge {hingeRest = signum (hingeRest hinge) * 27 * pi / 180} else hinge
  pure fixture {curlHinges = map open (curlHinges fixture)}
