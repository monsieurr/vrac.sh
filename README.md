# vrac.sh

## Objectif
Partager mes scripts bash, en vrac.
+ Commandes plus bas dans ce README.

## Liste
- ytmp3.sh : télécharger et convertir les vidéos youtube en .mp3, dans la meilleure qualité disponible (si possible) - nécessite yt-dlp
- twdl.sh : télécharger les VODs Twitch, fournir ID ou URL de la / des vidéos - nécessite yt-dlp
- dupl.sh : trouver les fichiers duplicats - brouillon


## Quelques commandes en vrac
Afficher les fichiers dans le dossier courant et tous les dossiers et fichiers en dessous, avec affichage des /, taille des fichiers et droits d'accès.
```bash
ls -PRFl
```

Ouvrir le lecteur Twitch avec Streamlink et le chat Twitch avec Chatterino, permet d'avoir une expérience plus légère de Twitch, notamment sur les machines ayant peu de puissance.
Si Chatterino n'est pas installé la seconde étape sera ignorée, possible aussi de retirer la boucle avec Chatterino pour simplifier si non utilisé.
```bash
sl() {
  streamlink "twitch.tv/$1" "${@:2}" &
  if [[ -e "/Applications/Chatterino.app" ]]; then
    open "/Applications/Chatterino.app"
  fi
}
```
