import json,sys,urllib.request,urllib.parse
def get(q, doi=None):
    url = ("https://api.openalex.org/works/doi:"+doi) if doi else ("https://api.openalex.org/works?per_page=1&search="+urllib.parse.quote(q))
    req = urllib.request.Request(url, headers={"User-Agent":"research-note (mailto:none@example.com)"})
    d = json.load(urllib.request.urlopen(req))
    if not doi: d = d['results'][0]
    inv = d.get('abstract_inverted_index') or {}
    pos = {p:w for w,ps in inv.items() for p in ps}
    print("TITLE:", d['title'], d.get('publication_year'), d.get('doi'))
    print("AUTHORS:", [a['author']['display_name'] for a in d['authorships']][:6])
    print("ABSTRACT:", ' '.join(pos[i] for i in sorted(pos))[:1500])
    print()
for a in sys.argv[1:]:
    try:
        if a.startswith('doi:'): get(None, a[4:])
        else: get(a)
    except Exception as e: print("ERR", a, e)
