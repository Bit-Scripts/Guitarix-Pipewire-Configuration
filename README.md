# Configuration de Guitarix avec PipeWire en mode émulation JACK
Ce projet contient un script Bash permettant de configurer automatiquement Guitarix pour utiliser PipeWire comme serveur audio en mode émulation JACK. PipeWire remplace progressivement JACK dans de nombreuses distributions Linux modernes, offrant une gestion simplifiée des flux audio et vidéo tout en maintenant la compatibilité avec les logiciels conçus pour JACK.

## Fonctionnalités
- **Détection automatique des périphériques audio :** le script identifie le périphérique d'entrée (guitare) et le périphérique de sortie par défaut.
- **Déconnexion des connexions existantes :** évite les conflits en déconnectant les ports JACK préexistants.
- **Connexion dynamique des ports :** établit automatiquement les connexions entre les périphériques d'entrée, Guitarix et les périphériques de sortie.
- **Compatibilité PipeWire :** exploite PipeWire en mode émulation JACK, sans nécessiter l'installation ou l'exécution d'un serveur JACK natif.
## Prérequis
- **PipeWire** avec support JACK activé.
- **Guitarix** installé.
- **pw-jack** pour exécuter des commandes JACK avec PipeWire.
- Une distribution Linux moderne (par exemple : Ubuntu, Fedora, Manjaro).
## Attention
Ce script utilise le retour des commandes dans un environnement Ubuntu 24.04.1 LTS configuré en français. Si votre système est configuré dans une autre langue ou une version différente, certains retours de commande peuvent différer, entraînant des erreurs. Adaptez le script à votre environnement si nécessaire.
## Installation
1. Clonez ce dépôt :
  
```bash
git clone https://github.com/Bit-Scripts/Guitarix-Pipewire-Configuration.git
cd Guitarix-Pipewire-Configuration
```
2. Rendez le script exécutable :
  
```bash
chmod +x guitarix_pw_config.sh
```
3. Déplacez le script dans un répertoire accessible globalement, comme /usr/local/bin :
  
```bash
sudo mv guitarix_pw_config.sh /usr/local/bin/
```
## Utilisation
1. Assurez-vous que PipeWire est en cours d'exécution et que Guitarix est installé.
2. Lancez le script :
```bash
/usr/local/bin/guitarix_pw_config.sh
```
3. Guitarix sera configuré automatiquement et prêt à être utilisé avec votre périphérique d'entrée et de sortie par défaut.
4. Le script peut être lancé depuis un fichier *.desktop (Optionnel) à mettre dans `/usr/local/share/applications/`
#### Contenu du fichier `.desktop`
```desktop
[Desktop Entry]
Type=Application
Name=Guitarix PipeWire Config
Comment=Configure Guitarix to use PipeWire in JACK emulation mode
Exec=/usr/local/bin/guitarix_pw_config.sh
Icon=guitarix
Terminal=true
Categories=Audio;Music;Utility;
StartupNotify=false
```
#### Instructions
1. **Créer le fichier :** Créez un fichier nommé guitarix-pw-config.desktop dans le répertoire `/usr/local/share/applications/`.
```bash
sudo nano /usr/local/share/applications/guitarix-pw-config.desktop
```
2. **Coller le contenu :** Collez le contenu ci-dessus dans le fichier et enregistrez.
3. **Rendre le fichier exécutable :**
  
```bash
sudo chmod +x /usr/local/share/applications/guitarix-pw-config.desktop
```
4. **Tester le lancement :** Le fichier `.desktop` devrait apparaître dans votre menu d'applications sous le nom **Guitarix PipeWire Config**. Cliquez dessus pour exécuter le script.
5. **Icône personnalisée (optionnel) :** Si vous souhaitez utiliser une icône spécifique, remplacez `Icon=guitarix` par le chemin complet de l'icône de votre choix. Par exemple :
  
```bash
Icon=/usr/local/share/icons/guitarix-icon.png
```
## Dépannage
- Si le script échoue à détecter vos périphériques, assurez-vous que PipeWire est correctement configuré pour gérer les périphériques JACK.
- Consultez les logs d'erreur affichés par le script pour identifier les problèmes de configuration.
## Licence
Ce projet est sous licence GNU GPLv3. Vous pouvez consulter la licence complète ici :
[GNU GPLv3](gnu-gpl-v3.0.md)
