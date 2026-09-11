# Review the two glTF scenes

This preview uses the unmodified Three.js GLTFLoader. It does not interpret
material metadata, hide triangles itself or offset layers. The GLB decides
which paper belongs in each scene. Start from the repository root:

```bash
stack build
python3 study/gltf/generate.py
npm install --prefix build/gltf-preview --no-audit --no-fund three@0.186.0
python3 -m http.server 8001 --directory build/gltf-preview
```

Open [the preview](http://127.0.0.1:8001/). Select Visible paper or Complete
paper, inspect from above and below, and rotate through the folding edges.
The first scene should have stable colours; the complete sheet deliberately
retains touching layers, which an ordinary depth buffer cannot order.
Both scenes use one camera centre and scale. Edge-on flat paper has no area;
physical thickness is not being added for display.

The generator exports all thirteen `*-base.fold` fixtures plus the quarter
fold, a pinwheel, a crane, and all sixteen
checked bird states. Give it a directory argument to place the preview under
an existing local server. For example, `build/fold-material/gltf-preview`
puts it at `/gltf-preview/` when serving the usual material-study directory;
install Three.js into that directory too. Dependencies and generated output
stay under ignored `build/`, not in source control.

For independent format validation, install the
[Khronos validator](https://github.com/KhronosGroup/glTF-Validator):

```bash
npm install --prefix build/gltf-preview --no-audit --no-fund gltf-validator@2.0.0-dev.3.10
node study/gltf/validate.cjs build/gltf-preview
```

The validator checks containers, accessors and glTF rules. The Haskell tests
separately check material references, colours' triangle winding, cuts, shared
positions and the supplied layer relationships. Neither is a proof of contact
between unsampled folding states. See [the export note](../../docs/notes/visible-paper-mesh.md).
