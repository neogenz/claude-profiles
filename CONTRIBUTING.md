# Contribuer à Profils Claude

## Installation

Voir `README.md`. Aucun paquet Python tiers n’est nécessaire.

## Modifications

1. Créer une branche depuis `main`.
2. Modifier le moteur dans `src/claude-profiles.py` ou l’interface dans `src/ClaudeProfiles.swift`.
3. Adapter les tests concernés, puis exécuter `python3 tests/check_profiles.py` et `python3 tests/check_install.py`.
4. Compiler l’interface sur macOS avec `python3 install.py --build-only`.
5. Vérifier l’interface avec des profils de test, jamais avec des identifiants publiés dans le dépôt.

Utiliser des commits conventionnels. Avant publication, vérifier les fichiers indexés et effectuer une recherche de secrets. Les configurations réelles, les dossiers de compte et les sorties de compilation doivent rester hors de Git.
