;; DriftHaven Travel Itinerary Planner

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-invalid-price (err u104))
(define-constant platform-fee u50) ;; 5% in basis points

;; Data Variables
(define-data-var next-experience-id uint u0)

;; Data Maps
(define-map Experiences
    uint 
    {
        provider: principal,
        title: (string-utf8 100),
        description: (string-utf8 500),
        location: (string-utf8 100),
        price: uint,
        available-slots: uint,
        active: bool
    }
)

(define-map ProviderVerification
    principal 
    {
        verified: bool,
        rating: uint,
        total-reviews: uint
    }
)

(define-map Bookings
    {experience-id: uint, user: principal}
    {
        paid-amount: uint,
        status: (string-ascii 20),
        booking-time: uint
    }
)

;; Provider Functions
(define-public (create-experience (title (string-utf8 100)) 
                                (description (string-utf8 500))
                                (location (string-utf8 100))
                                (price uint)
                                (slots uint))
    (let ((experience-id (var-get next-experience-id)))
        (asserts! (is-verified tx-sender) err-unauthorized)
        (asserts! (> price u0) err-invalid-price)
        (try! (map-insert Experiences
            experience-id
            {
                provider: tx-sender,
                title: title,
                description: description,
                location: location,
                price: price,
                available-slots: slots,
                active: true
            }
        ))
        (var-set next-experience-id (+ experience-id u1))
        (ok experience-id)
    )
)

(define-public (update-experience (experience-id uint)
                                (price uint)
                                (slots uint)
                                (active bool))
    (let ((experience (unwrap! (map-get? Experiences experience-id) err-not-found)))
        (asserts! (is-eq (get provider experience) tx-sender) err-unauthorized)
        (try! (map-set Experiences
            experience-id
            (merge experience {
                price: price,
                available-slots: slots,
                active: active
            })
        ))
        (ok true)
    )
)

;; Booking Functions
(define-public (book-experience (experience-id uint))
    (let (
        (experience (unwrap! (map-get? Experiences experience-id) err-not-found))
        (total-price (get price experience))
        (provider (get provider experience))
        (platform-cut (/ (* total-price platform-fee) u1000))
    )
        (asserts! (get active experience) err-unauthorized)
        (asserts! (> (get available-slots experience) u0) err-unauthorized)
        
        ;; Process payment
        (try! (stx-transfer? total-price tx-sender provider))
        (try! (stx-transfer? platform-cut provider contract-owner))
        
        ;; Update booking records
        (try! (map-set Bookings
            {experience-id: experience-id, user: tx-sender}
            {
                paid-amount: total-price,
                status: "booked",
                booking-time: block-height
            }
        ))
        
        ;; Update available slots
        (try! (map-set Experiences
            experience-id
            (merge experience {
                available-slots: (- (get available-slots experience) u1)
            })
        ))
        (ok true)
    )
)

;; Provider Verification
(define-public (verify-provider (provider principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (try! (map-set ProviderVerification
            provider
            {
                verified: true,
                rating: u0,
                total-reviews: u0
            }
        ))
        (ok true)
    )
)

;; Read Only Functions
(define-read-only (is-verified (provider principal))
    (default-to false (get verified (map-get? ProviderVerification provider)))
)

(define-read-only (get-experience (experience-id uint))
    (map-get? Experiences experience-id)
)

(define-read-only (get-booking (experience-id uint) (user principal))
    (map-get? Bookings {experience-id: experience-id, user: user})
)