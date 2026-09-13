-- | Small connected sheets for the library flap operation's exported demo.
-- These are our own coordinates. Each current pose comes from crease angles;
-- ids name the explicitly recorded faces and edges, without material picking.
module FlapExample (singleFlap, opposingFlap, touchingFlap, alignedFlap, blockedStack) where

import Senbazuru.Fold.Types (Assignment (..), FaceId (..), FaceOrder (..), Frame (..), Stacking (..), VertexId (..), emptyFrame)

singleFlap :: Frame
singleFlap =
  emptyFrame
    { verticesCoords = [[0, 0], [0.5, 0], [1, 0], [1, 1], [0.5, 1], [0, 1]],
      edgesVertices = [(VertexId a, VertexId b) | (a, b) <- [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 0), (1, 4)]],
      edgesAssignment = replicate 6 Border ++ [Valley],
      edgesFoldAngle = replicate 6 0 ++ [15],
      facesVertices = map (map VertexId) [[0, 1, 4, 5], [1, 2, 3, 4]]
    }

-- | The existing contact study's three-panel arrangement, with the middle
-- panel wider than either flap. A 16-degree right turn is safe; a full turn
-- returns to the same endpoint but hits the other flap on the way.
opposingFlap :: Frame
opposingFlap =
  emptyFrame
    { verticesCoords = [[0, 0], [0.3, 0], [0.7, 0], [1, 0], [1, 1], [0.7, 1], [0.3, 1], [0, 1]],
      edgesVertices = [(VertexId a, VertexId b) | (a, b) <- [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6), (6, 7), (7, 0), (1, 6), (2, 5)]],
      edgesAssignment = replicate 8 Border ++ [Valley, Valley],
      edgesFoldAngle = replicate 8 0 ++ [145, 105],
      facesVertices = map (map VertexId) [[0, 1, 6, 7], [1, 2, 5, 6], [2, 3, 4, 5]]
    }

-- | Fold the narrow right panel onto the middle panel, then lift that pair
-- about edge 8. The narrow panel stops short of the lifting crease, leaving
-- an exposed strip that makes the two layers visible without separating them.
-- Face 2 is above face 1 against face 1's wound normal, not the viewer's eye.
touchingFlap :: Frame
touchingFlap =
  opposingFlap
    { verticesCoords = [[0, 0], [0.4, 0], [0.8, 0], [1, 0], [1, 1], [0.8, 1], [0.4, 1], [0, 1]],
      edgesFoldAngle = replicate 8 0 ++ [0, 180],
      faceOrders = [FaceOrder (FaceId 2) (FaceId 1) Above]
    }

-- | Three equal-width panels. Folding the right panel onto the middle puts
-- its free edge (vertices 3 and 4) on the lifting crease (vertices 1 and 6).
-- Those are still different material vertices, even at identical positions.
alignedFlap :: Frame
alignedFlap =
  touchingFlap
    { verticesCoords = [[0, 0], [1 / 3, 0], [2 / 3, 0], [1, 0], [1, 1], [2 / 3, 1], [1 / 3, 1], [0, 1]]
    }

-- | The opposing-flap control with a fourth, equal-width panel folded onto
-- the right flap. Rotating the right pair about edge 11 must still detect the
-- fixed left flap, even though contact inside the moving pair is permitted.
blockedStack :: Frame
blockedStack =
  emptyFrame
    { verticesCoords = [[0, 0], [0.3, 0], [0.7, 0], [1, 0], [1.3, 0], [1.3, 1], [1, 1], [0.7, 1], [0.3, 1], [0, 1]],
      edgesVertices = [(VertexId a, VertexId b) | (a, b) <- [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6), (6, 7), (7, 8), (8, 9), (9, 0), (1, 8), (2, 7), (3, 6)]],
      edgesAssignment = replicate 10 Border ++ replicate 3 Valley,
      edgesFoldAngle = replicate 10 0 ++ [145, 105, 180],
      facesVertices = map (map VertexId) [[0, 1, 8, 9], [1, 2, 7, 8], [2, 3, 6, 7], [3, 4, 5, 6]],
      faceOrders = [FaceOrder (FaceId 3) (FaceId 2) Above]
    }
