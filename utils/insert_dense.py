#!/usr/bin/env python3
import io

tscn = io.open('scenes/levels/ground_war.tscn', encoding='utf-8').read()
block = io.open('dense_nodes.txt', encoding='utf-8').read()
anchor = '[node name="MultiplayerHUD" type="CanvasLayer" parent="." unique_id=1676682577]'

if anchor not in tscn:
    raise RuntimeError(f"Anchor '{anchor}' not found in ground_war.tscn")

new_tscn = tscn.replace(anchor, block + '\n' + anchor, 1)
io.open('scenes/levels/ground_war.tscn', 'w', encoding='utf-8', newline='').write(new_tscn)
print(f"Successfully inserted {len(block)} characters into ground_war.tscn")
