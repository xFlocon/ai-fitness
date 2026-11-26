"""Gera catálogo e mídia offline das revisões fixadas em docs/CATALOGO.md."""

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory

clips, flow, commons, wger = map(Path, sys.argv[1:])
root = Path(__file__).resolve().parents[1] / 'assets/exercises'
media = root / 'media'
media.mkdir(parents=True, exist_ok=True)


def load(source):
    return json.loads((source / 'data/exercises.json').read_text())


def ffmpeg(*args):
    subprocess.run(['ffmpeg', '-nostdin', '-loglevel', 'error', '-y', *args], check=True)


def flow_media(exercise, key):
    with TemporaryDirectory() as directory:
        folder = Path(directory)
        # Reproduz quadros sem transformar velocidade da animação em prescrição.
        for i, index in enumerate(exercise['animation']['sequence']):
            svg = (flow / exercise['animation']['frames'][index]).read_text()
            if exercise['id'] == '0276':
                # Recorta artefato fora da figura, na margem direita do quadro.
                svg = svg.replace('viewBox="0 0 627.000000 627.000000"',
                                  'viewBox="0 0 570 627"')
            vector = folder / 'frame.svg'
            vector.write_text(svg)
            subprocess.run(['rsvg-convert', '-b', '#252933', '-w', '336', '-h', '256',
                            '-a', '-o', folder / f'{i}.png', vector], check=True)
        shutil.copyfile(folder / '0.png', media / f'{key}.png')
        ffmpeg('-framerate', '2', '-i', folder / '%d.png', '-loop', '0', media / f'{key}.gif')


reviewed = {'0276': 'Dead bug', '3013': 'Ponte baixa de glúteos no chão',
            '0662': 'Flexão de braços', '0659': 'Flexão na parede', '3224': 'Polichinelo'}
clip_names = '''Supino reto com halteres|Supino inclinado com barra|Supino com halteres na bola suíça|Mergulho para peito nas paralelas|Desenvolvimento com barra|Elevação lateral com halteres|Crucifixo inverso na polia|Supino com pegada fechada|Tríceps testa com barra W|Mergulho com carga para tríceps|Rosca direta com barra|Rosca inclinada com halteres|Rosca martelo no banco Scott|Flexão de punhos sentado|Rosca inversa com barra W|Caminhada segurando anilhas|Encolhimento com barra|Encolhimento com halteres|Remada alta com barra|Remada baixa na polia|Remada T com apoio de peito|Remada curvada com barra|Puxada alta|Barra fixa com pegada aberta|Puxada na polia com braços estendidos|Superman|Abdominal completo|Elevação de pernas deitada|Abdominal curto com anilha|Rotação ascendente na polia ajoelhado|Rotação descendente na polia ajoelhado|Rotação ascendente na polia em base alternada|Elevação pélvica com barra|Extensão lombar|Bom dia com barra|Agachamento com barra nas costas|Leg press|Agachamento hack|Agachamento na parede com bola suíça|Levantamento terra com pernas rígidas|Flexão de pernas na cadeira flexora|Flexão de pernas com bola suíça|Flexão nórdica de pernas|Elevação de panturrilhas em pé|Elevação de panturrilhas sentado|Elevação de panturrilhas no leg press|Adução de quadril na máquina|Avanço lateral com alcance|Mobilidade em agachamento profundo|Abdução de quadril na polia|Caminhada com mobilidade de quadril|Círculos de quadril em quatro apoios|Mobilização do quadril ajoelhado|Liberação lateral da coxa com rolo|Liberação plantar|Liberação da palma da mão|Mobilidade cervical'''.split('|')
clip_gear = dict(bodyweight='body weight', ezBar='ez barbell', dipBars='dip bars',
                 pullupBar='pull-up bar', ball='stability ball', roller='roller',
                 lacrosse='massage ball', machine='leverage machine')
groups = dict(chest='chest', shoulders='shoulders', triceps='upper arms',
              biceps='upper arms', forearm='lower arms', traps='back',
              upperBack='back', lats='back', lowerBack='back', abs='waist',
              obliques='waist', glutes='upper legs', quads='upper legs',
              hamstrings='upper legs', calves='lower legs', adductors='upper legs',
              abductors='upper legs', hipFlexors='upper legs', itBand='upper legs',
              plantar='lower legs', palmar='lower arms', neck='neck')
extra_gear = {'c03': [], 'b03': ['bench'], 'g02': ['leverage machine'],
              'h04': ['anchor'], 'v01': ['leverage machine']}
records = []
for e, pt in zip(load(clips), clip_names, strict=True):
    key = 'clip-' + e['id']
    source = clips / e['video']['path']
    if hashlib.sha256(source.read_bytes()).hexdigest() != e['video']['sha256']:
        raise ValueError(f'Hash incorreto: {source}')
    shutil.copyfile(source, media / f'{key}.mp4')
    ffmpeg('-ss', '1', '-i', source, '-frames:v', '1', '-vf', 'scale=352:-1', media / f'{key}.jpg')
    group = groups[e['primaryMuscle']]
    gear = [clip_gear.get(g, g) for g in e['equipment']] + extra_gear.get(e['id'], [])
    records.append(dict(id=key, en=e['name'], pt=pt, gear=sorted(set(gear)),
                        group=group, target=e['primaryMuscle'], notes=e['cues'],
                        kind='mp4', still='jpg', mobility=e['type'] in ('mobility', 'recovery')))

for e in load(flow):
    key = 'flow-' + e['id']
    record = dict(id=key, en=e['name'], gear=[e['equipment']], group=e['bodyPart'],
                  target=e['target'], notes=e['instructions'], pattern=e['movementPattern'])
    if e['id'] in reviewed:
        flow_media(e, key)
        record.update(pt=reviewed[e['id']], kind='gif', still='png')
        if e['id'] == '0659':
            record['gear'].append('wall')
        if e['id'] == '3013':
            record['target'] = 'glutes'
    records.append(record)

for number, file, en, pt, group, digest in [
    ('01', 'Squats.gif', 'Bodyweight squat', 'Agachamento livre', 'upper legs', 'a5d98e1abccc82eaf946bacf65af914c9def49f5e5de8d6e9018ab9f1d38cdaf'),
    ('02', 'Burpees.gif', 'Burpee', 'Burpee', 'cardio', '0636b2a085e1ef1de4a34cc448f211f3a045346b2534b573c0bbcb6e8728760c'),
    ('03', 'High_knees.gif', 'Jumping high knees', 'Joelhos altos com salto', 'cardio', 'c0f33a7a456cdb0b30baa8467e8d0fe042ca374532ac854e8738511ab001ad11'),
]:
    source = commons / file
    if hashlib.sha256(source.read_bytes()).hexdigest() != digest:
        raise ValueError(f'Hash incorreto: {source}')
    key = 'commons-' + number
    gif = media / f'{key}.gif'
    shutil.copyfile(source, gif)
    still = media / f'{key}.png'
    ffmpeg('-ss', '0.12', '-i', gif, '-frames:v', '1', '-vf', 'scale=320:-1', still)
    if not still.is_file():
        raise ValueError(f'Miniatura ausente: {gif}')
    records.append(dict(id=key, en=en, pt=pt, gear=['body weight'], group=group,
                        target=group, notes=[], kind='gif', still='png',
                        credit='Wensceslao • CC BY-SA 4.0',
                        source='https://commons.wikimedia.org/wiki/File:' + file,
                        licenseUrl='https://creativecommons.org/licenses/by-sa/4.0/'))

for number, digest in [
    ('27', 'c33d15868b7856471bff7a3a5cf5efaf7082b8d1376a9cf990a2257a2a1dcd3c'),
    ('28', 'f3f401a35ccef993f1ca8c37db35e200f5f6d6321b66b3d609e0207b50032f57'),
]:
    source = wger / f'{number}.png'
    if hashlib.sha256(source.read_bytes()).hexdigest() != digest:
        raise ValueError(f'Hash incorreto: {source}')
    shutil.copyfile(source, media / f'wger-{number}.png')
records.append(dict(id='wger-27', en='Standing barbell curl', pt='Rosca direta com barra (imagens)',
                    gear=['barbell'], group='upper arms', target='biceps', notes=[],
                    kind='image', still='png', second='wger-28.png',
                    credit='Everkinetic / wger • CC BY-SA 3.0',
                    source='https://wger.de/api/v2/exerciseimage/27/',
                    licenseUrl='https://creativecommons.org/licenses/by-sa/3.0/'))

(root / 'catalog.json').write_text(json.dumps(records, ensure_ascii=False, separators=(',', ':')) + '\n')
for source, name, dest in [(clips, 'LICENSE', 'CLIPS-CC0.txt'), (flow, 'LICENSE', 'FLOW-MIT.txt'),
                           (flow, 'ARTWORK-LICENSE', 'FLOW-CC0.txt'), (flow, 'NOTICE.md', 'FLOW-NOTICE.md')]:
    shutil.copyfile(source / name, root / dest)
