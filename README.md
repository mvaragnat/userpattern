# UserPattern

Analyse anonymisée des patterns d'usage des utilisateurs connectés dans une application Rails.

UserPattern s'installe comme une gem Rails. Elle intercepte les requêtes des utilisateurs authentifiés, collecte des statistiques de fréquence par endpoint, et présente un tableau de bord triable — le tout sans jamais stocker d'identifiant utilisateur.

## Fonctionnalités

- **Multi-modèle** : tracke `User`, `Admin`, ou tout modèle authentifiable. Configurable.
- **Compatible Devise + JWT** : détecte automatiquement l'authentification par session cookie ou par header `Authorization`.
- **Anonymisation totale** : impossible de retrouver les actions d'un utilisateur donné (HMAC à sel rotatif quotidien).
- **Impact minimal sur la performance** : buffer en mémoire, écriture en batch asynchrone.
- **Dashboard intégré** : tableau HTML triable par fréquence, filtrable par type de modèle.
- **Nettoyage automatisable** : tâche rake pour purger les données expirées.

## Installation

Ajouter au `Gemfile` de votre application :

```ruby
gem "userpattern", path: "path/to/userpattern"  # en développement local
# gem "userpattern", github: "your-org/userpattern"  # via GitHub
```

Puis lancer le générateur d'installation :

```bash
bundle install
rails generate userpattern:install
rails db:migrate
```

Le générateur crée :
1. `config/initializers/userpattern.rb` — fichier de configuration
2. La migration pour la table `userpattern_request_events`
3. La route vers le dashboard (`/userpattern`)

## Configuration

```ruby
# config/initializers/userpattern.rb

UserPattern.configure do |config|
  # Modèles à traquer (par défaut : User via current_user)
  config.tracked_models = [{ name: "User", current_method: :current_user }]

  # Ajouter d'autres modèles
  config.track "Admin", current_method: :current_admin

  # Détection de session (voir section dédiée ci-dessous)
  config.session_detection = :auto

  # Performance : taille du buffer et intervalle de flush
  config.buffer_size    = 100  # flush quand le buffer atteint cette taille
  config.flush_interval = 30   # flush au moins toutes les N secondes

  # Rétention des données brutes (en jours)
  config.retention_period = 30

  # Authentification du dashboard (voir section sécurité)
  config.dashboard_auth = nil

  # Activer/désactiver le tracking
  config.enabled = true
end
```

## Détection de l'utilisateur connecté

### Stratégie par défaut : `current_user`

UserPattern utilise un callback `after_action` dans les contrôleurs. Pour chaque modèle configuré, il appelle la méthode spécifiée (par défaut `current_user`) :

```ruby
config.tracked_models = [{ name: "User", current_method: :current_user }]
```

### Devise + sessions classiques

Avec Devise, `current_user` est disponible dans tous les contrôleurs via le helper Warden. **Aucune configuration supplémentaire nécessaire.**

### Devise + JWT (devise-jwt, devise-token-auth)

Avec `devise-jwt` ou des gems similaires, le middleware Warden est configuré pour authentifier via le token JWT dans le header `Authorization`. **`current_user` fonctionne donc aussi en mode API, sans adaptation.**

Le flow :
1. Le client envoie `Authorization: Bearer <token>`
2. Warden (via la stratégie JWT de Devise) décode le token et hydrate `current_user`
3. UserPattern appelle `current_user` dans le `after_action` — l'utilisateur est détecté

### JWT custom (sans Devise)

Si vous utilisez un système JWT maison qui n'alimente pas `current_user`, vous pouvez :

1. Définir une méthode `current_user` dans votre `ApplicationController` qui décode le JWT
2. Ou spécifier une méthode custom :

```ruby
config.tracked_models = [
  { name: "ApiClient", current_method: :current_api_client }
]
```

### Modèles multiples

Pour traquer plusieurs types d'utilisateurs (ex: Devise avec scopes) :

```ruby
config.tracked_models = [{ name: "User", current_method: :current_user }]
config.track "Admin", current_method: :current_admin
config.track "ApiClient", current_method: :current_api_client
```

Chaque requête est comptabilisée pour **tous** les modèles correspondants (si un utilisateur est simultanément `User` et `Admin`, les deux sont trackés).

## Anonymisation

### Principe

UserPattern ne stocke **jamais** d'identifiant utilisateur (id, email, etc.). L'anonymisation repose sur un identifiant de session opaque :

```
anonymous_session_id = HMAC-SHA256(
  clé:    secret_key_base[0..31] + ":2026-04-08",
  valeur: session_id | authorization_header
)[0..15]
```

### Propriétés de sécurité

| Propriété | Garantie |
|---|---|
| **Irréversibilité** | HMAC one-way : impossible de retrouver le session_id ou l'utilisateur |
| **Rotation quotidienne** | Le sel change chaque jour → impossible de corréler les sessions d'un jour à l'autre |
| **Troncature** | Seuls 16 caractères hex sont conservés (64 bits), réduisant encore l'entropie |
| **Pas de lien user↔actions** | Aucun user_id en base. Même avec un accès complet à la DB, on ne peut que voir des stats agrégées |

### Détection de session

Le mode `:auto` (par défaut) choisit automatiquement :
- **Header `Authorization` présent** → hash du header (cas JWT/API)
- **Session cookie présent** → hash du session ID (cas navigateur classique)
- **Aucun des deux** → hash de l'IP (fallback)

Vous pouvez forcer un mode ou fournir un Proc custom :

```ruby
config.session_detection = :header   # toujours utiliser le header Authorization
config.session_detection = :session  # toujours utiliser le cookie de session
config.session_detection = ->(request) { request.headers["X-Request-ID"] }
```

## Performance

UserPattern est conçu pour avoir un impact négligeable sur les temps de réponse.

### Architecture du buffer

```
Requête HTTP
    ↓
after_action (< 0.1ms)
    ↓ push
[Buffer mémoire thread-safe]   ← Concurrent::Array
    ↓ flush (async, toutes les 30s ou 100 events)
[INSERT batch en DB]            ← ActiveRecord insert_all
```

- Le `after_action` ne fait qu'un `push` dans un array thread-safe (~microsecondes)
- Le flush se fait dans un thread séparé, sans bloquer la requête
- `insert_all` écrit tous les events en un seul INSERT SQL
- Les paramètres `buffer_size` et `flush_interval` sont configurables

### Requêtes sur le dashboard

Le dashboard calcule les stats à la volée à partir de la table `userpattern_request_events`. Trois index couvrent les requêtes principales :

- `(model_type, endpoint, recorded_at)` — agrégation temporelle
- `(model_type, endpoint, anonymous_session_id)` — comptage de sessions distinctes
- `(recorded_at)` — nettoyage des données expirées

### Nettoyage

Pour éviter que la table ne grossisse indéfiniment :

```bash
rails userpattern:cleanup
```

À planifier en cron (quotidien recommandé). Supprime les events plus vieux que `retention_period` (30 jours par défaut).

## Dashboard

Le dashboard est accessible à la route où vous montez l'engine :

```ruby
# config/routes.rb
mount UserPattern::Engine, at: "/userpattern"
```

Il affiche, par type de modèle :

| Colonne | Description |
|---|---|
| **Endpoint** | Méthode HTTP + chemin (ex: `GET /api/users`) |
| **Total Reqs** | Nombre total de requêtes enregistrées |
| **Sessions** | Nombre de sessions distinctes (anonymisées) |
| **Avg / Session** | Moyenne de requêtes par session |
| **Avg / Min** | Fréquence moyenne par minute |
| **Max / Min** | Fréquence maximale observée sur 1 minute |
| **Max / Hour** | Fréquence maximale observée sur 1 heure |
| **Max / Day** | Fréquence maximale observée sur 1 jour |

Toutes les colonnes sont triables (clic sur l'en-tête).

## Sécuriser le dashboard

**Le dashboard n'est pas protégé par défaut.** Vous devez configurer l'authentification.

### Option 1 : HTTP Basic Auth

```ruby
config.dashboard_auth = -> {
  authenticate_or_request_with_http_basic("UserPattern") do |user, pass|
    ActiveSupport::SecurityUtils.secure_compare(user, "admin") &
      ActiveSupport::SecurityUtils.secure_compare(pass, ENV["USERPATTERN_PASSWORD"])
  end
}
```

### Option 2 : Devise (restreindre aux admins)

```ruby
config.dashboard_auth = -> {
  redirect_to main_app.root_path, alert: "Accès refusé" unless current_user&.admin?
}
```

### Option 3 : Contrainte de route Rails

```ruby
# config/routes.rb
authenticate :user, ->(u) { u.admin? } do
  mount UserPattern::Engine, at: "/userpattern"
end
```

### Option 4 : IP whitelisting

```ruby
config.dashboard_auth = -> {
  unless request.remote_ip.in?(%w[127.0.0.1 ::1])
    head :forbidden
  end
}
```

## Prochaines étapes (non implémenté)

**Alertes de seuil** : définir des seuils par endpoint (ex: max 10 requêtes/minute) et recevoir une alerte quand un utilisateur connecté dépasse ce seuil. L'architecture actuelle (events individuels avec timestamps) permet d'implémenter cette fonctionnalité sans changement de schéma.

## Structure de la gem

```
userpattern/
├── app/
│   ├── controllers/userpattern/dashboard_controller.rb
│   ├── models/userpattern/request_event.rb
│   └── views/userpattern/dashboard/index.html.erb
├── config/routes.rb
├── lib/
│   ├── userpattern.rb
│   ├── userpattern/
│   │   ├── anonymizer.rb        # HMAC anonymization
│   │   ├── buffer.rb            # Thread-safe in-memory buffer
│   │   ├── configuration.rb     # Configuration DSL
│   │   ├── controller_tracking.rb # after_action concern
│   │   ├── engine.rb            # Rails Engine
│   │   ├── stats_calculator.rb  # SQL-agnostic stats computation
│   │   └── version.rb
│   ├── generators/userpattern/
│   │   ├── install_generator.rb
│   │   └── templates/
│   └── tasks/userpattern.rake
├── userpattern.gemspec
└── README.md
```

## Licence

MIT
