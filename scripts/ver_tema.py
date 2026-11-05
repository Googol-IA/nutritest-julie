import json,sys
d=json.load(open('web/contenido/'+sys.argv[1],encoding='utf-8'))
print(d.get('titulo'))
for q in d['preguntas']:
    o=q['opciones']; c=q['correcta']
    print(f"{q['id'][-3:]} {q['pregunta']} || " + ' | '.join(('*' if i==c else '')+x for i,x in enumerate(o)) + f" ## {q['explicacion']}")
