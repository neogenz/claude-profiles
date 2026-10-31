# Profils Claude

<img src="assets/logo.png" alt="Logo Profils Claude" width="160">

Gestionnaire local de profils Claude pour macOS. Interface native en français, moteur Python sans dépendance tierce.

- Ajouter un profil et son raccourci.
- Lancer plusieurs instances avec leurs dossiers Desktop et Code distincts.
- Afficher, copier et ouvrir les chemins des profils.
- Ouvrir les réglages JSON et les instructions dans TextEdit.
- Activer ou désactiver la copie de configuration depuis le profil personnel.

Outil personnel indépendant, non affilié à Anthropic. L’application Claude et les abonnements ne sont pas fournis.

## Installation sur un Mac

Prérequis : macOS 14 ou ultérieur, Python 3.9 ou ultérieur, outils de ligne de commande Xcode avec Swift et Claude installé dans `/Applications/Claude.app`.

Si les outils Apple sont absents, exécutez `xcode-select --install`, puis terminez leur installation. Un compilateur Swift/SDK trop ancien doit être mis à jour via les outils Apple.

Pour installer depuis ce dépôt :

```sh
git clone https://github.com/neogenz/claude-profiles.git
cd claude-profiles
python3 tests/check_profiles.py
python3 tests/check_install.py
python3 install.py
open "$HOME/Applications/Claude Profiles/Profils Claude.app"
```

La compilation s’effectue pour l’architecture du Mac courant. L’application du gestionnaire reçoit une signature locale ad hoc ; Claude lui-même n’est pas modifié. Utilisez un Python installé durablement, car l’application conserve un lien vers cet interpréteur. Relancez l’installation si ce Python est déplacé ou remplacé. Les raccourcis créés par cette version utilisent le lien stable vers Python. Les anciens raccourcis du prototype peuvent encore viser un ancien Python : utilisez alors le gestionnaire pour lancer ces profils.

Pour seulement compiler, sans installation :

```sh
python3 install.py --build-only
```

Pour mettre le gestionnaire à jour, fermez **Profils Claude**, récupérez le code, puis relancez `python3 install.py`. Les dossiers des profils existants restent en place.

## Utilisation

Cliquez sur **Ajouter un profil**, donnez un nom en minuscules, puis ouvrez Claude et connectez le compte souhaité. Le nom du profil est un repère local, pas une preuve de l’identité connectée. Vérifiez le compte dans Claude et dans l’onglet Code.

Emplacements créés pour un profil `travail` :

- Code : `~/.claude-travail`
- Desktop : `~/Library/Application Support/claude-travail`
- Raccourci : `~/Applications/Claude Profiles/Claude TRAVAIL.app`

Le profil **Personnel** garde ses emplacements existants. Le moteur et le lien Python se trouvent dans `~/Library/Application Support/Claude-Profile-Launcher`.

### Configuration commune

Une copie initiale des réglages, instructions, skills, agents, commandes, règles, styles et définitions MCP est créée depuis le profil personnel. Avec la synchronisation activée, cette copie est actualisée au démarrage d’une nouvelle instance. Afficher une instance déjà ouverte ne la synchronise pas. La synchronisation manuelle exige de fermer cette instance.

Les fichiers de même nom sont remplacés ; les fichiers supplémentaires ne sont pas supprimés. Modifiez la source commune via le configurateur, ou désactivez la synchronisation avant de personnaliser les copies. Réactiver la synchronisation remplace les modifications locales correspondantes lors de son prochain passage.

Désactiver la synchronisation conserve les copies. Les hooks et la barre d’état copiés peuvent encore référencer des scripts du profil personnel.

### Comptes et confidentialité

La connexion Claude, les cookies, l’historique et les installations de plugins ne sont pas copiés. Les champs d’authentification filtrés dans les réglages ne sont pas propagés. Les définitions MCP peuvent cependant contenir des identifiants de service : ces définitions sont réutilisées localement entre profils. Inspectez votre configuration avant de la partager entre comptes.

Ce dépôt contient uniquement du code et des tests fictifs. N’ajoutez pas vos dossiers de profils, journaux, configurations réelles, exports ou fichiers `.env`. Le caractère privé du dépôt ne justifie pas d’y stocker des secrets.

## Changer de Mac

Clonez le dépôt sur le nouveau Mac, installez le gestionnaire et recréez les profils via l’interface. Connectez chaque compte séparément et installez ses plugins.

Ce dépôt réinstalle l’outil ; il ne sauvegarde pas vos comptes ni votre configuration personnelle. Transférez vos instructions, skills et réglages souhaités séparément par un moyen privé, après vérification des chemins et secrets. Ne copiez pas les cookies ou le Trousseau via Git.

## Limites connues

- Les instances en cours d’exécution restent nommées **Claude** dans le Dock. Le gestionnaire distingue les profils et active l’instance par son PID.
- Pas de suppression ni de renommage des profils dans cette version.
- La copie de configuration est additive, sans résolution de conflits ni sauvegarde automatique des modifications locales écrasées.
- Les lanceurs réutilisant une instance peuvent demander l’autorisation macOS d’automatiser System Events ; l’activation depuis le gestionnaire utilise directement le PID.
- Les mécanismes de profils ont été vérifiés avec Claude 4.4212.0. Leur fonctionnement après une mise à jour de Claude reste à contrôler.
- Une compilation native réussie sur le Mac de développement ne valide pas tous les autres Mac, versions de macOS ou méthodes d’authentification.
