"""Converte animações do Flow em GIF, fora do aplicativo."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory

flow, output = map(Path, sys.argv[1:])
output.mkdir(parents=True, exist_ok=True)
reviewed = {
    '0002': ['Inclinação lateral em pé sem peso'],
    '0006': ['Toque alternado nos calcanhares deitado'],
    '0274': ['Abdominal curto no chão'],
    '0872': ['Abdominal reverso'],
    '0630': ['Escalador no chão'],
    '0710': ['Abdução de quadril em pé'],
    '1004': ['Agachamento com faixa elástica'],
    '3006': ['Abdução de quadril sentado com elástico', 'chair'],
    '0336': ['Avanço à frente com halteres'],
    '0413': ['Agachamento com halteres'],
    '0417': ['Elevação de panturrilhas em pé com halteres'],
    '0025': ['Supino reto com barra', 'bench'],
    '0212': ['Abdominal sentado na polia', 'bench'],
    '0585': ['Cadeira extensora'],
    '0597': ['Cadeira abdutora'],
    '1463': ['Leg press 45 graus'],
    '3636': ['Elevação de joelho com apoio na parede', 'wall'],
    '1490': ['Elevação de panturrilhas no degrau com apoio', 'step'],
    '0293': ['Remada curvada com halteres'],
    '0313': ['Rosca martelo em pé com halteres'],
    '0383': ['Crucifixo inverso inclinado com halteres'],
    '0405': ['Desenvolvimento sentado com halteres', 'bench'],
    '0534': ['Agachamento goblet com kettlebell'],
    '0586': ['Mesa flexora'],
    '0599': ['Cadeira flexora'],
    '3294': ['Flexão arqueiro'],
}
exercises = {e['id']: e for e in json.loads((flow / 'data/exercises.json').read_bytes())}
def export(e):
    number = e['id']
    key = f'flow-{number}'
    animation = e['animation']
    provenance = json.loads((flow / animation['provenance']).read_bytes())
    if animation['license'] != 'CC0-1.0' or provenance['artworkLicense'] != 'CC0-1.0':
        raise ValueError(f'Licença inesperada: {key}')
    frames = {f['path']: f['sha256'] for f in provenance['frames']}
    target = output / f'{key}.gif'
    with TemporaryDirectory() as directory:
        tmp = Path(directory)
        for i, frame in enumerate(animation['sequence']):
            path = animation['frames'][frame]
            if hashlib.sha256((flow / path).read_bytes()).hexdigest() != frames[path]:
                raise ValueError(f'Quadro diferente do original: {path}')
            subprocess.run(['rsvg-convert', '-b', '#252933', '-w', '256', '-h', '224',
                            '-a', '-o', tmp / f'{i}.png', flow / path], check=True)
        subprocess.run(['ffmpeg', '-nostdin', '-loglevel', 'error', '-y', '-framerate', '2',
                        '-i', tmp / '%d.png', '-loop', '0', target], check=True)
    data = target.read_bytes()
    if not data.startswith(b'GIF89a') or len(data) > 256 * 1024:
        raise ValueError(f'GIF fora do formato esperado: {key}')
    info = dict(sha256=hashlib.sha256(data).hexdigest())
    if number in reviewed:
        pt, *gear = reviewed[number]
        info.update(pt=pt, gear=sorted(set([e['equipment'], *gear])), reviewed=True)
    return key, info

with ThreadPoolExecutor(max_workers=4) as pool:
    manifest = dict(pool.map(export, (e for e in exercises.values() if e.get('animation'))))
(output / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
