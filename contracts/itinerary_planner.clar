;; DriftHaven Travel Itinerary Planner

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101)) 
(define-constant err-unauthorized (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-invalid-price (err u104))
(define-constant err-invalid-rating (err u105))
(define-constant err-not-booked (err u106))
(define-constant platform-fee u50) ;; 5% in basis points
(define-constant review-reward u100000000) ;; 0.1 STX reward for reviews

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
        active: bool,
        avg-rating: uint,
        total-ratings: uint
    }
)

(define-map ProviderVerification
    principal 
    {
        verified: bool,
        rating: uint,
        total-reviews: uint,
        total-earnings: uint
    }
)

(define-map Bookings
    {experience-id: uint, user: principal}
    {
        paid-amount: uint,
        status: (string-ascii 20),
        booking-time: uint,
        has-reviewed: bool
    }
)

(define-map Reviews
    {experience-id: uint, reviewer: principal}
    {
        rating: uint,
        comment: (string-utf8 500),
        review-time: uint
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
                active: true,
                avg-rating: u0,
                total-ratings: u0
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
        (provider-info (default-to {verified: false, rating: u0, total-reviews: u0, total-earnings: u0} 
                                 (map-get? ProviderVerification provider)))
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
                booking-time: block-height,
                has-reviewed: false
            }
        ))
        
        ;; Update provider earnings
        (try! (map-set ProviderVerification
            provider
            (merge provider-info {
                total-earnings: (+ (get total-earnings provider-info) (- total-price platform-cut))
            })
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

;; Review Functions
(define-public (submit-review (experience-id uint) 
                            (rating uint)
                            (comment (string-utf8 500)))
    (let (
        (booking (unwrap! (map-get? Bookings {experience-id: experience-id, user: tx-sender}) err-not-booked))
        (experience (unwrap! (map-get? Experiences experience-id) err-not-found))
        (provider-info (default-to {verified: false, rating: u0, total-reviews: u0, total-earnings: u0}
                                 (map-get? ProviderVerification (get provider experience))))
    )
        (asserts! (not (get has-reviewed booking)) err-already-exists)
        (asserts! (and (>= rating u1) (<= rating u5)) err-invalid-rating)
        
        ;; Store review
        (try! (map-set Reviews
            {experience-id: experience-id, reviewer: tx-sender}
            {
                rating: rating,
                comment: comment,
                review-time: block-height
            }
        ))
        
        ;; Update experience ratings
        (try! (map-set Experiences
            experience-id
            (merge experience {
                avg-rating: (/ (+ (* (get avg-rating experience) (get total-ratings experience)) rating)
                             (+ (get total-ratings experience) u1)),
                total-ratings: (+ (get total-ratings experience) u1)
            })
        ))
        
        ;; Update provider ratings
        (try! (map-set ProviderVerification
            (get provider experience)
            (merge provider-info {
                rating: (/ (+ (* (get rating provider-info) (get total-reviews provider-info)) rating)
                         (+ (get total-reviews provider-info) u1)),
                total-reviews: (+ (get total-reviews provider-info) u1)
            })
        ))
        
        ;; Mark booking as reviewed
        (try! (map-set Bookings
            {experience-id: experience-id, user: tx-sender}
            (merge booking {has-reviewed: true})
        ))
        
        ;; Send review reward
        (try! (stx-transfer? review-reward contract-owner tx-sender))
        
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
                total-reviews: u0,
                total-earnings: u0
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

(define-read-only (get-review (experience-id uint) (reviewer principal))
    (map-get? Reviews {experience-id: experience-id, reviewer: reviewer})
)

(define-read-only (get-provider-stats (provider principal))
    (map-get? ProviderVerification provider)
)
