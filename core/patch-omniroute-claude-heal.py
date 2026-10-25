#!/usr/bin/env python3
import os
import glob
import re

OMNI_DIR = '/data/data/com.termux/files/usr/lib/node_modules/omniroute'
if not os.path.exists(OMNI_DIR):
    print('[Patch] OmniRoute directory not found, skipping.')
    exit(0)

print('[*] Checking & applying OmniRoute Claude tool_use auto-healing patches...')

# 1. Patch compiled Next.js chunks in dist/.build/next/server/chunks/
chunk_dir = os.path.join(OMNI_DIR, 'dist/.build/next/server/chunks')
if os.path.exists(chunk_dir):
    chunks = glob.glob(os.path.join(chunk_dir, '*.js'))
    
    # 1a. Ensure function responses precede text in merged turns
    old_order = 'return[...t,...r]'
    new_order = 'return[...r,...t]'
    
    # 1b. Ensure tool responses auto-heal missing items with "Done"
    patterns = [
        ('if(t.some(e=>m(e))||h){let e=[];for(let n of t){let t=g(n);if(void 0===t||!o.supportsSignatureBypass&&c&&!i.has(n))continue;',
         'if(t.length>0){let e=[];for(let n of t){let t=g(n);if(void 0===t)t="Done";if(!o.supportsSignatureBypass&&c&&!i.has(n))continue;'),
        ('if(t.some(e=>m(e))||_){let e=[];for(let n of t){let t=g(n);if(void 0===t||!o.supportsSignatureBypass&&c&&!i.has(n))continue;',
         'if(t.length>0){let e=[];for(let n of t){let t=g(n);if(void 0===t)t="Done";if(!o.supportsSignatureBypass&&c&&!i.has(n))continue;')
    ]

    # 1c. Antigravity executor function F auto-heal
    old_F = 'function F(e){let t=e.contents;return Array.isArray(t)&&0!==t.length&&(0,M.stripTrailingGeminiModelTurns)(t),e}'
    new_F = 'function F(e){let t=e.contents;if(!Array.isArray(t)||0===t.length)return e;(0,M.stripTrailingGeminiModelTurns)(t);let h=[];for(let i=0;i<t.length;i++){let cur=t[i];h.push(cur);if(cur&&"model"===cur.role&&Array.isArray(cur.parts)){let fcs=[];for(let p of cur.parts){p&&"object"==typeof p&&p.functionCall&&fcs.push(p.functionCall)}if(fcs.length>0){let nxt=i+1<t.length?t[i+1]:null,ans=new Set;if(nxt&&"user"===nxt.role&&Array.isArray(nxt.parts)){for(let p of nxt.parts){p&&"object"==typeof p&&p.functionResponse&&(p.functionResponse.id&&ans.add(String(p.functionResponse.id)),p.functionResponse.name&&ans.add(String(p.functionResponse.name)))}}let mis=fcs.filter(e=>{let t=e.id?String(e.id):null,r=e.name?String(e.name):"tool";return!(t&&ans.has(t))&&!ans.has(r)});if(mis.length>0){let e=mis.map(e=>({functionResponse:{name:e.name||"tool",...e.id?{id:e.id}:{},response:{result:"Done"}}}));h.push({role:"user",parts:e})}}}}return e.contents=h,e}'

    patched_chunks = 0
    for c in chunks:
        with open(c, 'r', encoding='utf-8') as f:
            content = f.read()
        changed = False
        
        if old_order in content:
            content = content.replace(old_order, new_order)
            changed = True
            
        for old_p, new_p in patterns:
            if old_p in content:
                content = content.replace(old_p, new_p)
                changed = True
                
        if old_F in content:
            content = content.replace(old_F, new_F)
            changed = True
            
        if changed:
            with open(c, 'w', encoding='utf-8') as f:
                f.write(content)
            patched_chunks += 1

    print(f'[✓] Verified and patched {patched_chunks} compiled Next.js chunks.')

# 2. Patch TypeScript sources in open-sse/
sse_dir = os.path.join(OMNI_DIR, 'open-sse')
if os.path.exists(sse_dir):
    # 2a. helpers.ts
    h_file = os.path.join(sse_dir, 'translator/request/openai-to-gemini/helpers.ts')
    if os.path.exists(h_file):
        with open(h_file, 'r', encoding='utf-8') as f:
            ht = f.read()
        if 'return [...others, ...responses];' in ht:
            ht = ht.replace('return [...others, ...responses];', 'return [...responses, ...others];')
            with open(h_file, 'w', encoding='utf-8') as f:
                f.write(ht)
            print('[✓] Patched open-sse helpers.ts')

    # 2b. toolResultAdjacency.ts
    adj_file = os.path.join(sse_dir, 'translator/request/openai-to-claude/toolResultAdjacency.ts')
    if os.path.exists(adj_file):
        with open(adj_file, 'r', encoding='utf-8') as f:
            at = f.read()
        target = 'return grouped.filter((toolResult) => toolResult.tool_use_id === String(block.id));'
        repl = '''const matched = grouped.filter((toolResult) => toolResult.tool_use_id === String(block.id));
    if (matched.length > 0) return matched;
    return [{ type: "tool_result", tool_use_id: String(block.id), content: "[Tool execution completed]" }];'''
        if target in at and 'Tool execution completed' not in at:
            at = at.replace(target, repl)
            with open(adj_file, 'w', encoding='utf-8') as f:
                f.write(at)
            print('[✓] Patched open-sse toolResultAdjacency.ts')

print('[✓] OmniRoute Claude tool_use persistence enforcement complete.')
