;; Game Asset Registry Contract
;; Manages creation, ownership, and metadata of in-game assets

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ASSET-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-EXISTS (err u102))
(define-constant ERR-INVALID-INPUT (err u103))
(define-constant ERR-INSUFFICIENT-BALANCE (err u104))
(define-constant ERR-TRANSFER-FAILED (err u105))

;; Data Variables
(define-data-var next-asset-id uint u1)
(define-data-var contract-paused bool false)

;; Asset rarity levels
(define-constant RARITY-COMMON u1)
(define-constant RARITY-UNCOMMON u2)
(define-constant RARITY-RARE u3)
(define-constant RARITY-EPIC u4)
(define-constant RARITY-LEGENDARY u5)

;; Asset categories
(define-constant CATEGORY-WEAPON u1)
(define-constant CATEGORY-ARMOR u2)
(define-constant CATEGORY-CHARACTER u3)
(define-constant CATEGORY-CONSUMABLE u4)
(define-constant CATEGORY-COLLECTIBLE u5)

;; Data Maps
(define-map assets
  { asset-id: uint }
  {
    owner: principal,
    creator: principal,
    name: (string-ascii 64),
    description: (string-ascii 256),
    image-uri: (string-ascii 256),
    category: uint,
    rarity: uint,
    level: uint,
    experience: uint,
    created-at: uint,
    last-updated: uint,
    tradeable: bool,
    game-id: (string-ascii 32)
  }
)

(define-map asset-metadata
  { asset-id: uint }
  {
    attributes: (string-ascii 512),
    stats: (string-ascii 256),
    special-abilities: (string-ascii 256)
  }
)

(define-map user-assets
  { owner: principal }
  { asset-count: uint }
)

(define-map game-registrations
  { game-id: (string-ascii 32) }
  {
    game-name: (string-ascii 64),
    developer: principal,
    active: bool,
    registered-at: uint
  }
)

(define-map creator-royalties
  { creator: principal }
  { royalty-percentage: uint }
)

;; Private Functions
(define-private (is-valid-rarity (rarity uint))
  (and (>= rarity RARITY-COMMON) (<= rarity RARITY-LEGENDARY))
)

(define-private (is-valid-category (category uint))
  (and (>= category CATEGORY-WEAPON) (<= category CATEGORY-COLLECTIBLE))
)

(define-private (increment-user-asset-count (owner principal))
  (let ((current-count (default-to u0 (get asset-count (map-get? user-assets { owner: owner })))))
    (map-set user-assets { owner: owner } { asset-count: (+ current-count u1) })
  )
)

(define-private (decrement-user-asset-count (owner principal))
  (let ((current-count (default-to u0 (get asset-count (map-get? user-assets { owner: owner })))))
    (if (> current-count u0)
      (map-set user-assets { owner: owner } { asset-count: (- current-count u1) })
      true
    )
  )
)

;; Public Functions

;; Register a new game
(define-public (register-game (game-id (string-ascii 32)) (game-name (string-ascii 64)))
  (begin
    (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
    (asserts! (> (len game-id) u0) ERR-INVALID-INPUT)
    (asserts! (> (len game-name) u0) ERR-INVALID-INPUT)
    (asserts! (is-none (map-get? game-registrations { game-id: game-id })) ERR-ALREADY-EXISTS)

    (map-set game-registrations
      { game-id: game-id }
      {
        game-name: game-name,
        developer: tx-sender,
        active: true,
        registered-at: block-height
      }
    )
    (ok game-id)
  )
)

;; Mint a new asset
(define-public (mint-asset
  (to principal)
  (name (string-ascii 64))
  (description (string-ascii 256))
  (image-uri (string-ascii 256))
  (category uint)
  (rarity uint)
  (game-id (string-ascii 32))
  (tradeable bool)
)
  (let ((asset-id (var-get next-asset-id)))
    (begin
      (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
      (asserts! (> (len name) u0) ERR-INVALID-INPUT)
      (asserts! (is-valid-rarity rarity) ERR-INVALID-INPUT)
      (asserts! (is-valid-category category) ERR-INVALID-INPUT)
      (asserts! (is-some (map-get? game-registrations { game-id: game-id })) ERR-ASSET-NOT-FOUND)

      (map-set assets
        { asset-id: asset-id }
        {
          owner: to,
          creator: tx-sender,
          name: name,
          description: description,
          image-uri: image-uri,
          category: category,
          rarity: rarity,
          level: u1,
          experience: u0,
          created-at: block-height,
          last-updated: block-height,
          tradeable: tradeable,
          game-id: game-id
        }
      )

      (increment-user-asset-count to)
      (var-set next-asset-id (+ asset-id u1))
      (ok asset-id)
    )
  )
)

;; Transfer asset ownership
(define-public (transfer-asset (asset-id uint) (to principal))
  (let ((asset-data (unwrap! (map-get? assets { asset-id: asset-id }) ERR-ASSET-NOT-FOUND)))
    (begin
      (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
      (asserts! (is-eq tx-sender (get owner asset-data)) ERR-NOT-AUTHORIZED)
      (asserts! (get tradeable asset-data) ERR-NOT-AUTHORIZED)
      (asserts! (not (is-eq tx-sender to)) ERR-INVALID-INPUT)

      (map-set assets
        { asset-id: asset-id }
        (merge asset-data {
          owner: to,
          last-updated: block-height
        })
      )

      (decrement-user-asset-count tx-sender)
      (increment-user-asset-count to)
      (ok true)
    )
  )
)

;; Update asset metadata
(define-public (set-asset-metadata
  (asset-id uint)
  (attributes (string-ascii 512))
  (stats (string-ascii 256))
  (special-abilities (string-ascii 256))
)
  (let ((asset-data (unwrap! (map-get? assets { asset-id: asset-id }) ERR-ASSET-NOT-FOUND)))
    (begin
      (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
      (asserts! (is-eq tx-sender (get owner asset-data)) ERR-NOT-AUTHORIZED)

      (map-set asset-metadata
        { asset-id: asset-id }
        {
          attributes: attributes,
          stats: stats,
          special-abilities: special-abilities
        }
      )
      (ok true)
    )
  )
)

;; Level up asset
(define-public (level-up-asset (asset-id uint) (experience-gained uint))
  (let ((asset-data (unwrap! (map-get? assets { asset-id: asset-id }) ERR-ASSET-NOT-FOUND)))
    (let ((new-experience (+ (get experience asset-data) experience-gained))
          (current-level (get level asset-data)))
      (let ((new-level (if (>= new-experience (* current-level u100)) (+ current-level u1) current-level)))
        (begin
          (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
          (asserts! (is-eq tx-sender (get owner asset-data)) ERR-NOT-AUTHORIZED)
          (asserts! (> experience-gained u0) ERR-INVALID-INPUT)

          (map-set assets
            { asset-id: asset-id }
            (merge asset-data {
              level: new-level,
              experience: new-experience,
              last-updated: block-height
            })
          )
          (ok new-level)
        )
      )
    )
  )
)

;; Set creator royalty percentage
(define-public (set-creator-royalty (royalty-percentage uint))
  (begin
    (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
    (asserts! (<= royalty-percentage u1000) ERR-INVALID-INPUT) ;; Max 10% (1000 basis points)

    (map-set creator-royalties
      { creator: tx-sender }
      { royalty-percentage: royalty-percentage }
    )
    (ok true)
  )
)

;; Burn asset (permanent destruction)
(define-public (burn-asset (asset-id uint))
  (let ((asset-data (unwrap! (map-get? assets { asset-id: asset-id }) ERR-ASSET-NOT-FOUND)))
    (begin
      (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
      (asserts! (is-eq tx-sender (get owner asset-data)) ERR-NOT-AUTHORIZED)

      (map-delete assets { asset-id: asset-id })
      (map-delete asset-metadata { asset-id: asset-id })
      (decrement-user-asset-count tx-sender)
      (ok true)
    )
  )
)

;; Read-only Functions

;; Get asset information
(define-read-only (get-asset (asset-id uint))
  (map-get? assets { asset-id: asset-id })
)

;; Get asset metadata
(define-read-only (get-asset-metadata (asset-id uint))
  (map-get? asset-metadata { asset-id: asset-id })
)

;; Get user asset count
(define-read-only (get-user-asset-count (owner principal))
  (default-to u0 (get asset-count (map-get? user-assets { owner: owner })))
)

;; Get game registration info
(define-read-only (get-game-info (game-id (string-ascii 32)))
  (map-get? game-registrations { game-id: game-id })
)

;; Get creator royalty percentage
(define-read-only (get-creator-royalty (creator principal))
  (default-to u0 (get royalty-percentage (map-get? creator-royalties { creator: creator })))
)

;; Check if asset exists
(define-read-only (asset-exists (asset-id uint))
  (is-some (map-get? assets { asset-id: asset-id }))
)

;; Get next asset ID
(define-read-only (get-next-asset-id)
  (var-get next-asset-id)
)

;; Check if contract is paused
(define-read-only (is-contract-paused)
  (var-get contract-paused)
)

;; Admin Functions (only contract owner)

;; Pause/unpause contract
(define-public (set-contract-pause (paused bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set contract-paused paused)
    (ok paused)
  )
)

;; Deactivate a game
(define-public (deactivate-game (game-id (string-ascii 32)))
  (let ((game-data (unwrap! (map-get? game-registrations { game-id: game-id }) ERR-ASSET-NOT-FOUND)))
    (begin
      (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

      (map-set game-registrations
        { game-id: game-id }
        (merge game-data { active: false })
      )
      (ok true)
    )
  )
)
