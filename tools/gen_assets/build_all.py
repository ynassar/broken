"""
build_all.py - regenerate every texture and model.

    python3 tools/gen_assets/build_all.py

Order matters only in that textures should exist before Godot imports the
models that reference them.  Afterwards run the Godot import + preview (see
README.md) to check the results.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import gen_textures  # noqa: E402
import gen_environment  # noqa: E402
import gen_food  # noqa: E402


def main():
    gen_textures.main()
    gen_environment.main()
    gen_food.main()
    env = sum(t for _, t, _, _, _ in gen_environment.MANIFEST)
    food = sum(t for _, t, _, _ in gen_food.MANIFEST)
    print('done: %d environment tris, %d food tris, %d models' % (
        env, food, len(gen_environment.MANIFEST) + len(gen_food.MANIFEST)))


if __name__ == '__main__':
    main()
