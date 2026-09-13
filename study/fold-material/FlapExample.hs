-- | Small connected sheets for the library flap operation's exported demo.
-- These are our own coordinates. Each current pose comes from crease angles;
-- ids name the explicitly recorded faces and edges, without material picking.
module FlapExample (singleFlap, opposingFlap) where

import Senbazuru.Fold.Types (Assignment (..), Frame (..), VertexId (..), emptyFrame)

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
