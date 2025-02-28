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
(define-constant err-empty-string (err u107))
(define-constant err-insufficient-balance (err u108))
(define-constant platform-fee u50) ;; 5% in basis points
(define-constant review-reward u100000000) ;; 0.1 STX reward for reviews

;; Rest of the original contract code remains the same until create-experience

(define-public (create-experience (title (string-utf8 100)) 
                              (description (string-utf8 500))
                              (location (string-utf8 100))
                              (price uint)
                              (slots uint))
    (let ((experience-id (var-get next-experience-id)))
        (asserts! (is-verified tx-sender) err-unauthorized)
        (asserts! (> price u0) err-invalid-price)
        (asserts! (not (is-eq (len title) u0)) err-empty-string)
        (asserts! (not (is-eq (len description) u0)) err-empty-string)
        (asserts! (not (is-eq (len location) u0)) err-empty-string)
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

;; Rest of the contract remains same until submit-review

(define-public (submit-review (experience-id uint) 
                            (rating uint)
                            (comment (string-utf8 500)))
    (let (
        (booking (unwrap! (map-get? Bookings {experience-id: experience-id, user: tx-sender}) err-not-booked))
        (experience (unwrap! (map-get? Experiences experience-id) err-not-found))
        (provider-info (default-to {verified: false, rating: u0, total-reviews: u0, total-earnings: u0}
                               (map-get? ProviderVerification (get provider experience))))
        (contract-balance (stx-get-balance contract-owner))
    )
        (asserts! (not (get has-reviewed booking)) err-already-exists)
        (asserts! (and (>= rating u1) (<= rating u5)) err-invalid-rating)
        (asserts! (>= contract-balance review-reward) err-insufficient-balance)
        
        ;; Safe rating calculations
        (let (
            (new-total-ratings (+ (get total-ratings experience) u1))
            (new-total-reviews (+ (get total-reviews provider-info) u1))
            (exp-rating-sum (* (get avg-rating experience) (get total-ratings experience)))
            (prov-rating-sum (* (get rating provider-info) (get total-reviews provider-info)))
        )
            ;; Store review
            (try! (map-set Reviews
                {experience-id: experience-id, reviewer: tx-sender}
                {
                    rating: rating,
                    comment: comment,
                    review-time: block-height
                }
            ))
            
            ;; Update experience ratings safely
            (try! (map-set Experiences
                experience-id
                (merge experience {
                    avg-rating: (/ (+ exp-rating-sum rating) new-total-ratings),
                    total-ratings: new-total-ratings
                })
            ))
            
            ;; Update provider ratings safely
            (try! (map-set ProviderVerification
                (get provider experience)
                (merge provider-info {
                    rating: (/ (+ prov-rating-sum rating) new-total-reviews),
                    total-reviews: new-total-reviews
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
)

;; Rest of the contract remains the same
